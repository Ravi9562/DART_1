// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';

import 'package:pub_dartlang_org/shared/utils.dart';

void main() {
  group('Randomize Stream', () {
    test('Single batch', () async {
      final randomizedStream = randomizeStream(
        new Stream.fromIterable(new List.generate(10, (i) => i)),
        duration: new Duration(milliseconds: 100),
        random: new Random(123),
      );
      expect(await randomizedStream.toList(), [4, 3, 2, 8, 7, 5, 9, 1, 0, 6]);
    });

    test('Two batches', () async {
      final controller = new StreamController<int>();
      final randomizedStream = randomizeStream(
        controller.stream,
        duration: new Duration(milliseconds: 100),
        random: new Random(123),
      );
      final valuesFuture = randomizedStream.toList();
      new List.generate(8, (i) => i).forEach(controller.add);
      await new Future.delayed(new Duration(milliseconds: 200));
      new List.generate(8, (i) => i + 10).forEach(controller.add);
      controller.close();
      // 0-7, 10-17 in separate batches
      expect(await valuesFuture,
          [1, 0, 7, 5, 6, 3, 4, 2, 10, 14, 11, 17, 13, 16, 15, 12]);
    });

    test('Small slices', () async {
      final controller = new StreamController<int>();
      final randomizedStream = randomizeStream(
        controller.stream,
        duration: new Duration(milliseconds: 100),
        maxPositionDiff: 4,
        random: new Random(123),
      );
      final valuesFuture = randomizedStream.toList();
      new List.generate(8, (i) => i).forEach(controller.add);
      new List.generate(8, (i) => i + 10).forEach(controller.add);
      controller.close();
      // 0-3, 4-7, 10-13, 14-17 in separate batches
      expect(await valuesFuture,
          [3, 1, 0, 2, 4, 5, 6, 7, 11, 13, 12, 10, 16, 14, 17, 15]);
    });
  });
}
