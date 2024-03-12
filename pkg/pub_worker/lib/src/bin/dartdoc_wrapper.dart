// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:convert' show json, utf8, Utf8Codec;
import 'dart:io';

import 'package:_pub_shared/dartdoc/dartdoc_page.dart';
import 'package:clock/clock.dart';
import 'package:logging/logging.dart' show Logger;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';

final _log = Logger('dartdoc');
final _utf8 = Utf8Codec(allowMalformed: true);
final _jsonUtf8 = json.fuse(utf8);

Future<void> postProcessDartdoc({
  required String outputFolder,
  required String package,
  required String version,
  required String docDir,
  required String dartdocVersion,
  required DateTime cutoffTimestamp,
}) async {
  _log.info('Running dartdoc post-processing');
  final tmpOutDir = p.join(outputFolder, '_doc');
  await Directory(tmpOutDir).create(recursive: true);
  final files = listFilesWithTimeout(
    path: docDir,
    cutoffTimestamp: cutoffTimestamp,
  );
  await for (final file in files) {
    if (cutoffTimestamp.isBefore(clock.now())) {
      _log.warning(
          'Cut-off timestamp reached during dartdoc file post-processing.');
      return;
    }
    final suffix = file.path.substring(docDir.length + 1);
    final targetFile = File(p.join(tmpOutDir, suffix));
    await targetFile.parent.create(recursive: true);
    final isDartDocSidebar =
        file.path.endsWith('.html') && file.path.endsWith('-sidebar.html');
    final isDartDocPage = file.path.endsWith('.html') && !isDartDocSidebar;
    if (isDartDocPage) {
      final page = DartDocPage.parse(await file.readAsString(encoding: _utf8));
      await targetFile.writeAsBytes(_jsonUtf8.encode(page.toJson()));
    } else if (isDartDocSidebar) {
      final sidebar = DartDocSidebar.parse(
        await file.readAsString(encoding: _utf8),
        removeLeadingHrefParent: dartdocVersion == '8.0.4' &&
            file.path.endsWith('-extension-type-sidebar.html'),
      );
      await targetFile.writeAsBytes(_jsonUtf8.encode(sidebar.toJson()));
    } else {
      await file.copy(targetFile.path);
    }
  }
  // Move from temporary output directory to final one, ensuring that
  // documentation files won't be present unless all files have been processed.
  // This helps if there is a timeout along the way.
  await Directory(tmpOutDir).rename(p.join(outputFolder, 'doc'));
  _log.info('Finished post-processing');

  _log.info('Creating .tar.gz archive');
  Stream<TarEntry> _list() async* {
    final originalDocDir = Directory(docDir);
    final originalFiles = listFilesWithTimeout(
      path: docDir,
      cutoffTimestamp: cutoffTimestamp,
    );
    await for (final file in originalFiles) {
      if (cutoffTimestamp.isBefore(clock.now())) {
        _log.warning(
            'Cut-off timestamp reached during dartdoc archive building.');
        break;
      }
      // inside the archive prefix the name with <package>/version/
      final relativePath = p.relative(file.path, from: originalDocDir.path);
      final tarEntryPath = p.join(package, version, relativePath);
      final data = await file.readAsBytes();
      yield TarEntry.data(
        TarHeader(
          name: tarEntryPath,
          size: data.length,
        ),
        data,
      );
    }
  }

  final tmpTar = File(p.join(outputFolder, '_package.tar.gz'));
  await _list()
      .transform(tarWriter)
      .transform(gzip.encoder)
      .pipe(tmpTar.openWrite());
  await tmpTar.rename(p.join(outputFolder, 'doc', 'package.tar.gz'));

  _log.info('Finished .tar.gz archive');
}

@visibleForTesting
Stream<File> listFilesWithTimeout({
  required String path,
  required DateTime cutoffTimestamp,
}) async* {
  final root = Directory(path);
  final queue = Queue<Directory>.from([root]);
  while (queue.isNotEmpty) {
    if (cutoffTimestamp.isBefore(clock.now())) {
      _log.warning(
          'Cut-off timestamp reached during dartdoc file post-processing.');
      return;
    }

    final dir = queue.removeFirst();
    await for (final e in dir.list(followLinks: false)) {
      if (cutoffTimestamp.isBefore(clock.now())) {
        _log.warning(
            'Cut-off timestamp reached during dartdoc file post-processing.');
        return;
      }
      if (e is Directory) {
        queue.add(e);
      } else if (e is File) {
        yield e;
      }
    }
  }
}
