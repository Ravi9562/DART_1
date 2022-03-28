// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test is fragile because creating instances and waiting for them to start is
// slow, and something that could throw all sorts of exceptions, we don't want
// run this as part of normal testing.
@Tags(['fragile'])
import 'dart:async';
import 'dart:io' show Platform;

import 'package:appengine/appengine.dart';
import 'package:pub_dev/task/cloudcompute/cloudcompute.dart';
import 'package:pub_dev/task/cloudcompute/googlecloudcompute.dart';
import 'package:test/test.dart';

import '../../shared/test_services.dart';

void main() {
  test('CloudCompute from createGoogleCloudCompute()', () async {
    setupLogging();

    await withAppEngineServices(() async {
      // Create CloudCompute instance
      final gce = createGoogleCloudCompute(
        client: authClientService,
        project: Platform.environment['GOOGLE_CLOUD_PROJECT']!,
        poolLabel: 'manual-testing',
      );

      // Fail if any instances exist
      var instances = await gce.listInstances().toList();
      expect(instances, isEmpty);

      // Create instance that terminates
      scheduleMicrotask(() async {
        print('creating instance');
        final instance = await gce.createInstance(
          instanceName: gce.generateInstanceName(),
          zone: gce.zones.first,
          dockerImage: 'busybox:1.31.1',
          arguments: [
            'sh',
            '-c',
            'whoami; date -R; sleep 5s; date -R; uname -a',
          ],
          description: 'test instance that terminates rather quickly',
        );
        print('Created instance: ${instance.instanceName}, $instance');
      });

      // Wait until we have a terminated instance
      print('### Wait for instance to terminate on its own');
      while (!instances.any((i) => i.state == InstanceState.terminated)) {
        instances = await gce.listInstances().toList();
        print('listInstances():');
        for (final inst in instances) {
          print(' - ${inst.instanceName}, state: ${inst.state}');
        }
        await Future.delayed(Duration(seconds: 1));
      }
      // Delete instances
      print('### Delete all instances');
      for (final inst in instances) {
        await gce.delete(inst.zone, inst.instanceName);
      }

      // Wait until instances are deleted from listing
      print('### Wait for instance to disappear from listings');
      while (instances.isNotEmpty) {
        instances = await gce.listInstances().toList();
        print('listInstances():');
        for (final inst in instances) {
          print(' - ${inst.instanceName}, state: ${inst.state}');
        }
        await Future.delayed(Duration(seconds: 1));
      }
    });
  },
      timeout: Timeout.parse('30m'),
      skip: Platform.environment['GOOGLE_CLOUD_PROJECT'] == null ||
              // Avoid running against production by accident
              Platform.environment['GOOGLE_CLOUD_PROJECT'] == 'dartlang-pub'
          ? 'createGoogleCloudCompute testing requires GOOGLE_CLOUD_PROJECT'
          : false);
}
