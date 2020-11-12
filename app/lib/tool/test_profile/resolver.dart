// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:basics/basics.dart';
import 'package:pana/pana.dart' show ToolEnvironment;
import 'package:path/path.dart' as p;
import 'package:pub_dev/shared/configuration.dart';
import 'package:pub_dev/shared/utils.dart';

import 'models.dart';

/// Utility method to resolve package:version pairs that are:
/// - latest versions of the packages that are without specific versions
/// - direct or transitive dependencies of the packages
///
/// The resulting list contains all the resolved versions (may be more packages
/// than the profile originally specified).
Future<List<ResolvedVersion>> resolveVersions(TestProfile profile) async {
  return await withTempDirectory((temp) async {
    final pubCacheDir = Directory(p.join(temp.path, 'pub-cache'));
    await pubCacheDir.create();

    final toolEnv = await ToolEnvironment.create(
      dartSdkDir: envConfig.toolEnvDartSdkDir,
      flutterSdkDir: envConfig.flutterSdkDir,
      pubCacheDir: pubCacheDir.path,
    );

    for (final package in profile.packages) {
      final versions = package.versions == null || package.versions.isEmpty
          ? <String>['any']
          : package.versions;
      for (final version in versions) {
        final dummyDir = Directory(p.join(temp.path, 'dummy'));
        await dummyDir.create();

        final pubspecFile = File(p.join(dummyDir.path, 'pubspec.yaml'));
        await pubspecFile.writeAsString(_generateDummyPubspec(
          package.name,
          version,
          minSdkVersion: toolEnv.runtimeInfo.sdkVersion,
        ));

        final pr = await toolEnv.runUpgrade(dummyDir.path, false);
        if (pr.exitCode != 0) {
          throw Exception(
              'pub get on `${package.name} $version` exited with ${pr.exitCode}.\n${pr.stderr}');
        }

        await dummyDir.delete(recursive: true);
      }
    }
    final pubHostedDir =
        Directory(p.join(pubCacheDir.path, 'hosted', 'pub.dartlang.org'));
    final dirs = await pubHostedDir.list().toList();
    return dirs
        .whereType<Directory>()
        .map((d) => p.basename(d.path))
        .where((v) => v.contains('-'))
        .map((v) {
      final parts = v.partition('-');
      return ResolvedVersion(package: parts.first, version: parts.last);
    }).toList()
          ..sort();
  });
}

String _generateDummyPubspec(
  String package,
  String version, {
  String minSdkVersion,
}) {
  minSdkVersion ??= Platform.version.split(' ').first;
  return json.encode(
    {
      'name': '____dummy____',
      'environment': {
        'sdk': '>=$minSdkVersion <3.0.0',
      },
      'dependencies': {
        package: version,
      },
    },
  );
}
