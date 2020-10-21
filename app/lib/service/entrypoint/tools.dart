// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:logging/logging.dart';

import '../services.dart';

/// Helper for utilities in bin/tools to setup a minimal AppEngine environment,
/// calling [fn] to run inside it.
Future<void> withProdServices(Future<void> Function() fn) {
  return withServices(() {
    return fn();
  });
}

/// Setup the tool's runtime environment, including Datastore access and logging.
Future<void> withToolRuntime(Future<void> Function() fn) async {
  final subs = Logger.root.onRecord.listen((r) {
    print([
      r.time.toIso8601String().replaceFirst('T', ' '),
      r.toString(),
      r.error,
      r.stackTrace?.toString(),
    ].where((e) => e != null).join(' '));
  });
  try {
    await withProdServices(fn);
  } finally {
    await subs.cancel();
  }
}
