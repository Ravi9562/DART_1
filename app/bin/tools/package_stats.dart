// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Reads the latest stable version of packages and creates a JSON report.
/// Example use:
///   dart bin/tools/package_stats.dart --output report.json

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:gcloud/db.dart';

import 'package:pub_dartlang_org/frontend/models.dart';
import 'package:pub_dartlang_org/frontend/service_utils.dart';

Future main(List<String> args) async {
  final parser = new ArgParser()
    ..addOption('output', help: 'The report output file (or stdout otherwise)');
  final argv = parser.parse(args);

  var count = 0;
  var flutterCount = 0;
  final flutterPlugins = <String>[];
  final flutterSdks = <String>[];
  await withProdServices(() async {
    await for (Package p in dbService.query(Package).run()) {
      count++;
      if (count % 25 == 0) {
        print('Reading package #$count: ${p.name}');
      }

      final List<PackageVersion> versions =
          await dbService.lookup([p.latestVersionKey]);
      if (versions.isEmpty) continue;

      final latest = versions.first;
      final pubspec = latest.pubspec;

      if (pubspec.hasFlutterPlugin) {
        flutterPlugins.add(p.name);
      }
      if (pubspec.dependsOnFlutterSdk) {
        flutterSdks.add(p.name);
      }
      if (pubspec.hasFlutterPlugin || pubspec.dependsOnFlutterSdk) {
        flutterCount++;
      }
    }
  });

  final report = {
    'counters': {
      'total': count,
      'flutter': {
        'total': flutterCount,
        'plugins': flutterPlugins.length,
        'sdk': flutterSdks.length,
      }
    },
    'flutter': {
      'plugins': flutterPlugins,
      'sdk': flutterSdks,
    }
  };
  final json = new JsonEncoder.withIndent('  ').convert(report);
  if (argv['output'] != null) {
    final outputFile = new File(argv['output']);
    print('Writing report to ${outputFile.path}');
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(json + '\n');
  } else {
    print(json);
  }
}
