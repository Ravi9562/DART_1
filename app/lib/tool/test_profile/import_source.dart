// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../../shared/urls.dart' as urls;

import 'models.dart';
import 'resolver.dart' as resolver;

/// Interface for resolving and getting data for profiles.
abstract class ImportSource {
  /// Resolve all the package-version required for the [profile].
  Future<List<ResolvedVersion>> resolveVersions(TestProfile profile);

  /// Gets the archive bytes for [package]-[version].
  Future<List<int>> getArchiveBytes(String package, String version);

  /// Close resources that were opened during the sourcing of data.
  Future<void> close();
}

/// Resolves and downloads data from pub.dev.
class PubDevImportSource implements ImportSource {
  final String archiveCachePath;
  Client _client;

  PubDevImportSource({
    @required this.archiveCachePath,
  });

  @override
  Future<List<ResolvedVersion>> resolveVersions(TestProfile profile) =>
      resolver.resolveVersions(profile);

  @override
  Future<List<int>> getArchiveBytes(String package, String version) async {
    final archiveName = '$package-$version.tar.gz';
    final file = File(p.join(archiveCachePath, archiveName));
    // download package archive if not already in the cache
    if (!await file.exists()) {
      _client ??= Client();
      final rs = await _client.get(
          '${urls.siteRoot}${urls.pkgArchiveDownloadUrl(package, version)}');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(rs.bodyBytes);
    }
    return await file.readAsBytes();
  }

  @override
  Future<void> close() async {
    _client?.close();
  }
}

/// Generates data based on random seed, without any network (or file) access.
class SemiRandomImportSource implements ImportSource {
  @override
  Future<List<ResolvedVersion>> resolveVersions(TestProfile profile) async {
    final versions = <ResolvedVersion>[];
    profile.packages.forEach((p) {
      final vs = <String>[
        if (p.versions != null) ...p.versions,
      ];
      if (vs.isEmpty) {
        final r = Random(p.name.hashCode.abs());
        vs.add('1.${r.nextInt(5)}.${r.nextInt(10)}');
      }
      vs.forEach((v) {
        versions.add(ResolvedVersion(package: p.name, version: v));
      });
    });
    return versions;
  }

  @override
  Future<List<int>> getArchiveBytes(String package, String version) async {
    final archive = _ArchiveBuilder();

    final pubspec = json.encode({
      'name': package,
      'version': version,
      'environment': {
        'sdk': '>=2.6.0 <3.0.0',
      },
    });
    archive.addFile('pubspec.yaml', pubspec);
    archive.addFile('README.md', '# $package\n\nAwesome package.');
    archive.addFile('CHANGELOG.md', '## $version\n\n- updated');
    archive.addFile('lib/$package.dart', 'main() {\n  print(\'Hello.\');\n}\n');
    archive.addFile(
        'example/example.dart', 'main() {\n  print(\'example\');\n}\n');
    archive.addFile('LICENSE', 'All rights reserved.');
    return archive.toTarGzBytes();
  }

  @override
  Future<void> close() async {}
}

class _ArchiveBuilder {
  final archive = Archive();

  void addFile(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile.noCompress(path, bytes.length, bytes));
  }

  List<int> toTarGzBytes() {
    return gzip.encode(TarEncoder().encode(archive));
  }
}
