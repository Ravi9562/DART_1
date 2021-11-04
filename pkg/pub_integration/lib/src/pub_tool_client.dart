// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Wrapper for the `dart` command-line tool, with a focus on `dart pub`.
class DartToolClient {
  final String _pubHostedUrl;
  final String _tempDir;

  DartToolClient._(
    this._pubHostedUrl,
    this._tempDir,
  );

  String get _pubCacheDir => p.join(_tempDir, 'pub-cache');
  String get _configHome => p.join(_tempDir, 'config-home');

  /// Creates a new PubToolClient context with a temporary directory.
  static Future<DartToolClient> create({
    required String pubHostedUrl,
    required String credentialsFileContent,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp();

    final tool = DartToolClient._(pubHostedUrl, tempDir.path);
    await Directory(tool._pubCacheDir).create(recursive: true);

    // If we set $XDG_CONFIG_HOME, $APPDATA and $HOME to _configHome, we only
    // need to write the config file to two locations to supported:
    //  - $XDG_CONFIG_HOME/dart/pub-credentials.json
    //  - $APPDATA/dart/pub-credentials.json
    //  - $HOME/Library/Application Support/dart/pub-credentials.json
    await Future.wait([
      p.join(tool._configHome, 'dart'),
      p.join(tool._configHome, 'Library', 'Application Support', 'dart'),
    ].map((folder) async {
      final configFile = File(p.join(folder, 'pub-credentials.json'));

      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(credentialsFileContent);
    }));
    // Also write to legacy location in $PUB_CACHE/credentials.json
    await File(p.join(tool._pubCacheDir, 'credentials.json')).writeAsString(
      credentialsFileContent,
    );
    print('PUB_CACHE=${tool._pubCacheDir}');
    return tool;
  }

  /// Delete temp resources.
  Future<void> close() async {
    await Future.wait([
      _configHome,
      _tempDir,
    ].map((d) => Directory(d).delete(recursive: true)));
  }

  /// Runs a process.
  Future<void> runDart(
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    String? expectedError,
  }) async {
    final cmd = 'dart ${arguments.join(' ')}';
    print('Running $cmd in $workingDirectory...');

    final pr = await Process.run(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: workingDirectory,
      environment: {
        ...environment ?? {},
        'PUB_CACHE': _pubCacheDir,
        'PUB_HOSTED_URL': _pubHostedUrl,
        'XDG_CONFIG_HOME': _configHome,
        'HOME': _configHome,
        'APPDATA': _configHome,
      },
    );

    if (pr.exitCode == 0) {
      return;
    }
    if (expectedError == pr.stderr.toString().trim()) {
      return;
    }
    throw Exception(
      '$cmd failed with exit code $exitCode.\n'
      'STDOUT: ${pr.stdout}\n'
      'STDERR: ${pr.stderr}',
    );
  }

  Future<void> run(String pkgDir, String file) async {
    await runDart(['run', file], workingDirectory: pkgDir);
  }

  Future<void> getDependencies(String pkgDir) async {
    await runDart(['pub', 'get'], workingDirectory: pkgDir);
  }

  Future<void> publish(String pkgDir, {String? expectedError}) async {
    await runDart(
      ['pub', 'publish', '--force'],
      workingDirectory: pkgDir,
      expectedError: expectedError,
    );
  }

  Future<void> addUploader(String pkgDir, String email) async {
    await runDart(
      ['pub', 'uploader', 'add', email],
      workingDirectory: pkgDir,
      expectedError: "We've sent an invitation email to $email.\n"
          "They'll be added as an uploader after they accept the invitation.",
    );
  }

  Future<void> removeUploader(String pkgDir, String email) async {
    await runDart(
      ['pub', 'uploader', 'remove', email],
      workingDirectory: pkgDir,
    );
  }
}
