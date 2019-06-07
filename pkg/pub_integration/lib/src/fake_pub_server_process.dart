// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

final _random = Random.secure();

/// Wrapper and helper methods around the fake_pub_server process.
class FakePubServerProcess {
  final int port;
  final Process _process;
  final _startedCompleter = Completer();
  StreamSubscription _stdoutListener;
  final _linePatterns = <_LinePattern>[];

  FakePubServerProcess._(this.port, this._process);

  static Future<FakePubServerProcess> start({
    String pkgDir,
    int port,
    int storagePort,
  }) async {
    final pubDartArgs = (Platform.environment['PUB_DART_ARGUMENTS'] ?? '')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    pkgDir ??= p.join(Directory.current.path, '../fake_pub_server');
    // TODO: check for free port
    port ??= 20000 + _random.nextInt(990);
    storagePort ??= port + 1;

    final pr1 = await Process.run('pub', ['get'], workingDirectory: pkgDir);
    if (pr1.exitCode != 0) {
      throw Exception('pub get failed in fake_pub_server');
    }
    final process = await Process.start(
      'dart',
      [
        ...pubDartArgs,
        'bin/fake_pub_server.dart',
        '--port=$port',
        '--storage-port=$storagePort',
      ],
      workingDirectory: pkgDir,
    );
    final instance = FakePubServerProcess._(port, process);
    instance._bindListeners();
    return instance;
  }

  void _bindListeners() {
    _stdoutListener = _process.stdout
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen(
      (line) {
        print(line);
        if (line.contains('fake_pub_server running on port $port')) {
          _startedCompleter.complete();
        }
        for (int i = _linePatterns.length - 1; i>=0;i--) {
          final p = _linePatterns[i];
          if (p.matcher(line)) {
            _linePatterns.removeAt(i);
            p.completer.complete(line);
          }
        }
      },
    );
    Timer(Duration(seconds: 30), () {
      if (!_startedCompleter.isCompleted) {
        _startedCompleter.completeError('Timout starting fake_pub_server');
      }
    });
  }

  Future get started => _startedCompleter.future;

  Future<String> waitForLine(LineMatcher matcher) {
    final p = _LinePattern(matcher);
    _linePatterns.add(p);
    return p.completer.future;
  }

  Future kill() async {
    _stdoutListener?.cancel();
    // First try SIGTERM, and after 10 minutes do SIGKILL.
    _process.kill(ProcessSignal.sigterm);
    final timer = Timer(Duration(minutes: 10), () {
      _process.kill();
    });
    await _process.exitCode;
    timer.cancel();
  }
}

/// Matches the output line.
typedef LineMatcher = bool Function(String line);

class _LinePattern {
  final LineMatcher matcher;
  final completer  = Completer<String>();
  _LinePattern(this.matcher);
}
