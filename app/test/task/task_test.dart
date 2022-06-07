// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pana/pana.dart';
import 'package:pub_dev/task/backend.dart';
import 'package:pub_dev/task/cloudcompute/fakecloudcompute.dart';
import 'package:pub_dev/task/models.dart';
import 'package:pub_dev/tool/test_profile/import_source.dart';
import 'package:pub_dev/tool/test_profile/importer.dart';
import 'package:pub_dev/tool/test_profile/models.dart';
import 'package:pub_worker/pana_report.dart';
import 'package:pub_worker/payload.dart';
import 'package:pub_worker/src/upload.dart' show upload;
import 'package:test/test.dart';

import '../shared/test_services.dart';
import 'fake_time.dart';

Future<void> delay({
  int days = 0,
  int hours = 0,
  int minutes = 0,
  int seconds = 0,
  int milliseconds = 0,
}) =>
    Future.delayed(Duration(
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    ));

extension on FakeCloudInstance {
  /// First argument is always a JSON blob with the [Payload].
  Payload get payload =>
      Payload.fromJson(json.decode(arguments.first) as Map<String, dynamic>);
}

/// Get hold of the [FakeCloudCompute]
FakeCloudCompute get cloud => taskWorkerCloudCompute as FakeCloudCompute;

void main() {
  testWithFakeTime('tasks can scheduled and processed', (fakeTime) async {
    await taskBackend.backfillTrackingState();
    await fakeTime.elapse(minutes: 1);

    await taskBackend.start();
    await fakeTime.elapse(minutes: 5);

    // 5 minutes after start of scheduling we expect there to be 3 instances
    final instances = await cloud.listInstances().toList();
    expect(instances, hasLength(3));

    for (final instance in instances) {
      cloud.fakeStartInstance(instance.instanceName);
    }

    await fakeTime.elapse(minutes: 5);

    for (final instance in instances) {
      final payload = instance.payload;

      for (final v in payload.versions) {
        // Use token to get the upload information
        final api = createPubApiClient(authToken: v.token);
        final uploadInfo = await api.taskUploadResult(
          payload.package,
          v.version,
        );

        // Upload the minimum result, log file and empty pana-report
        final c = http.Client();
        try {
          await upload(
            c,
            uploadInfo.panaLog,
            utf8.encode('This is a pana log file'),
            filename: 'pana-log.txt',
            contentType: 'text/plain',
          );
          await upload(
            c,
            uploadInfo.panaReport,
            utf8.encode(json.encode(PanaReport(
              logId: uploadInfo.panaLogId,
              summary: null,
            ))),
            filename: 'pana-summary.json',
            contentType: 'application/json',
          );
        } finally {
          c.close();
        }

        // Report the task as finished
        await api.taskUploadFinished(payload.package, v.version);
      }
    }

    await fakeTime.elapse(minutes: 5);

    // All instances should be terminated, api.taskUploadFinished terminate
    // when all versions for the instance is done. And fake instances take 1
    // minute to simulate termination.
    expect(await cloud.listInstances().toList(), hasLength(0));

    await taskBackend.stop();

    await fakeTime.elapse(minutes: 10);
  });

  testWithFakeTime('failing instances will be retried', (fakeTime) async {
    await taskBackend.backfillTrackingState();
    await fakeTime.elapse(minutes: 1);

    await taskBackend.start();

    // We are going to let the task timeout, if this happens we should only
    // try to scheduled it until we hit the [taskRetryLimit].
    for (var i = 0; i < taskRetryLimit; i++) {
      // Within 24 hours an instance should be created
      await fakeTime.elapseUntil(
        () => cloud.listInstances().isNotEmpty,
        timeout: Duration(days: 1),
      );

      // If nothing happens, then it should be killed within 24 hours.
      // Actually, it'll happen much sooner, like ~2 hours, but we'll leave the
      // test some wiggle room.
      await fakeTime.elapseUntil(
        () => cloud.listInstances().isEmpty,
        timeout: Duration(days: 1),
      );
    }

    // Once we've exceeded the [taskRetryLimit], we shouldn't see any instances
    // created for the next day...
    assert(taskRetriggerInterval > Duration(days: 1));
    await expectLater(
      fakeTime.elapseUntil(
        () => cloud.listInstances().isNotEmpty,
        timeout: Duration(days: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );

    // But the task should be retried after [taskRetriggerInterval], this is a
    // long time, but for sanity we do re-analyze everything occasionally.
    await fakeTime.elapseUntil(
      () => cloud.listInstances().isNotEmpty,
      timeout: taskRetriggerInterval + Duration(days: 1),
    );

    await taskBackend.stop();

    await fakeTime.elapse(minutes: 10);
  },
      testProfile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [
          TestPackage(
            name: 'neon',
            versions: [TestVersion(version: '1.0.0')],
            publisher: 'example.com',
          ),
        ],
        users: [
          TestUser(email: 'admin@pub.dev', likes: []),
        ],
      ));

  testWithFakeTime('Limit on number of versions analyzed', (fakeTime) async {
    await taskBackend.backfillTrackingState();
    await fakeTime.elapse(minutes: 1);
    await taskBackend.start();
    await fakeTime.elapse(minutes: 15);

    // We expect there to be one instance with less than 10 versions to be
    // analyzed, this even though there really is 20 versions.
    final instances = await cloud.listInstances().toList();
    expect(instances, hasLength(1));
    expect(instances.first.payload.versions.length, lessThan(10));

    await taskBackend.stop();

    await fakeTime.elapse(minutes: 10);
  },
      testProfile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [
          TestPackage(
            name: 'neon',
            versions: [
              for (var i = 0; i < 20; i++) TestVersion(version: '1.0.$i'),
            ],
            publisher: 'example.com',
            isDiscontinued: true,
          ),
        ],
        users: [
          TestUser(email: 'admin@pub.dev', likes: []),
        ],
      ));

  testWithFakeTime('continued scan finds new packages', (fakeTime) async {
    await taskBackend.backfillTrackingState();
    await taskBackend.start();
    await fakeTime.elapse(minutes: 15);

    expect(await cloud.listInstances().toList(), hasLength(0));

    // Create a package
    await importProfile(
      source: ImportSource.autoGenerated(),
      profile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [
          TestPackage(
            name: 'neon',
            versions: [TestVersion(version: '1.0.0')],
            publisher: 'example.com',
          ),
        ],
      ),
    );

    await fakeTime.elapse(minutes: 15);

    expect(await cloud.listInstances().toList(), hasLength(1));

    await taskBackend.stop();

    await fakeTime.elapse(minutes: 10);
  },
      testProfile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [],
        users: [
          TestUser(email: 'admin@pub.dev', likes: []),
        ],
      ));

  testWithFakeTime('analyzed packages stay idle', (fakeTime) async {
    await taskBackend.backfillTrackingState();
    await taskBackend.start();
    await fakeTime.elapse(minutes: 15);

    final instances = await cloud.listInstances().toList();
    // There is only one package, so we should only get one instance
    expect(instances, hasLength(1));

    final instance = instances.first;
    final payload = instance.payload;

    // There should only be one version
    expect(payload.versions, hasLength(1));

    final v = payload.versions.first;
    // Use token to get the upload information
    final api = createPubApiClient(authToken: v.token);
    final uploadInfo = await api.taskUploadResult(
      payload.package,
      v.version,
    );

    // Upload the minimum result, log file and empty pana-report
    final c = http.Client();
    try {
      await upload(
        c,
        uploadInfo.panaLog,
        utf8.encode('This is a pana log file'),
        filename: 'pana-log.txt',
        contentType: 'text/plain',
      );
      await upload(
        c,
        uploadInfo.panaReport,
        utf8.encode(json.encode(PanaReport(
          logId: uploadInfo.panaLogId,
          summary: null,
        ))),
        filename: 'pana-summary.json',
        contentType: 'application/json',
      );
    } finally {
      c.close();
    }

    // Report the task as finished
    await api.taskUploadFinished(payload.package, v.version);

    // Leave time for the instance to be deleteds (takes 1 min in fake cloud)
    await fakeTime.elapse(minutes: 5);

    // We don't expect anything to be scheduled for the next 7 days.
    await fakeTime.expectUntil(
      () => cloud.listInstances().isEmpty,
      Duration(days: 7),
    );

    await taskBackend.stop();

    await fakeTime.elapse(minutes: 10);
  },
      testProfile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [
          TestPackage(
            name: 'neon',
            versions: [TestVersion(version: '1.0.0')],
            publisher: 'example.com',
          ),
        ],
        users: [
          TestUser(email: 'admin@pub.dev', likes: []),
        ],
      ));

  testWithFakeTime('continued scan finds new versions', (fakeTime) async {
    await taskBackend.backfillTrackingState();
    await taskBackend.start();
    await fakeTime.elapse(minutes: 15);
    {
      final instances = await cloud.listInstances().toList();
      // There is only one package, so we should only get one instance
      expect(instances, hasLength(1));

      final instance = instances.first;
      final payload = instance.payload;

      // There should only be one version
      expect(payload.versions, hasLength(1));

      final v = payload.versions.first;
      // Use token to get the upload information
      final api = createPubApiClient(authToken: v.token);
      final uploadInfo = await api.taskUploadResult(
        payload.package,
        v.version,
      );

      // Upload the minimum result, log file and empty pana-report
      final c = http.Client();
      try {
        await upload(
          c,
          uploadInfo.panaLog,
          utf8.encode('This is a pana log file'),
          filename: 'pana-log.txt',
          contentType: 'text/plain',
        );
        await upload(
          c,
          uploadInfo.panaReport,
          utf8.encode(json.encode(PanaReport(
            logId: uploadInfo.panaLogId,
            summary: null,
          ))),
          filename: 'pana-summary.json',
          contentType: 'application/json',
        );
      } finally {
        c.close();
      }

      // Report the task as finished
      await api.taskUploadFinished(payload.package, v.version);
    }
    // Leave time for the instance to be deleteds (takes 1 min in fake cloud)
    await fakeTime.elapse(minutes: 5);

    // We don't expect anything to be scheduled for the next 3 days.
    await fakeTime.expectUntil(
      () => cloud.listInstances().isEmpty,
      Duration(days: 3),
    );

    // Create a new version of existing package, this should trigger analysis
    await importProfile(
      source: ImportSource.autoGenerated(),
      profile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [
          TestPackage(
            name: 'neon',
            versions: [TestVersion(version: '2.0.0')],
            publisher: 'example.com',
          ),
        ],
      ),
    );

    await fakeTime.elapse(minutes: 15);

    {
      final instances = await cloud.listInstances().toList();
      // There is only one package, so we should only get one instance
      expect(instances, hasLength(1));

      final instance = instances.first;
      final payload = instance.payload;

      // There should only be one version
      expect(payload.versions, hasLength(1));
      //expect(payload.versions.map((v) => v.version), contains('2.0.0'));

      final v = payload.versions.first;
      expect(v.version, equals('2.0.0'));
    }

    await taskBackend.stop();

    await fakeTime.elapse(minutes: 10);
  },
      testProfile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [
          TestPackage(
            name: 'neon',
            versions: [TestVersion(version: '1.0.0')],
            publisher: 'example.com',
          ),
        ],
        users: [
          TestUser(email: 'admin@pub.dev', likes: []),
        ],
      ));

  testWithFakeTime('re-analyzes when dependency is updated', (fakeTime) async {
    await taskBackend.backfillTrackingState();
    await taskBackend.start();
    await fakeTime.elapse(minutes: 15);

    // There should be 2 packages for analysis now
    expect(await cloud.listInstances().toList(), hasLength(2));

    // We finish both packages, by uploading a response.
    for (final instance in await cloud.listInstances().toList()) {
      final payload = instance.payload;

      // There should only be one version
      expect(payload.versions, hasLength(1));

      final v = payload.versions.first;
      // Use token to get the upload information
      final api = createPubApiClient(authToken: v.token);
      final uploadInfo = await api.taskUploadResult(
        payload.package,
        v.version,
      );

      // Upload the minimum result, log file and empty pana-report
      final c = http.Client();
      try {
        await upload(
          c,
          uploadInfo.panaLog,
          utf8.encode('This is a pana log file'),
          filename: 'pana-log.txt',
          contentType: 'text/plain',
        );
        await upload(
          c,
          uploadInfo.panaReport,
          utf8.encode(json.encode(PanaReport(
            logId: uploadInfo.panaLogId,
            summary: Summary(
              runtimeInfo: PanaRuntimeInfo(
                panaVersion: '0.0.0',
                sdkVersion: '0.0.0',
              ),
              allDependencies: [
                // oxygen has a dependency on neon!
                if (payload.package == 'oxygen') 'neon',
              ],
            ),
          ))),
          filename: 'pana-summary.json',
          contentType: 'application/json',
        );
      } finally {
        c.close();
      }

      // Report the task as finished
      await api.taskUploadFinished(payload.package, v.version);
    }

    // Leave time for the instance to be deleteds (takes 1 min in fake cloud)
    await fakeTime.elapse(minutes: 15);

    // We don't expect anything to be scheduled now
    expect(await cloud.listInstances().toList(), isEmpty);

    // Create a new version of neon package, this should trigger analysis
    // of neon, but also of oxygen
    await importProfile(
      source: ImportSource.autoGenerated(),
      profile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [
          TestPackage(
            name: 'neon',
            versions: [TestVersion(version: '2.0.0')],
            publisher: 'example.com',
          ),
        ],
      ),
    );

    await fakeTime.elapse(minutes: 15);

    // Expect that neon is scheduled within 15 minutes
    expect(
      await cloud.listInstances().map((i) => i.payload.package).toList(),
      contains('neon'),
    );

    // Since oxygen was recently scheduled, we expect that it won't have been
    // scheduled yet.
    await fakeTime.elapse(minutes: 15);
    expect(
      await cloud.listInstances().map((i) => i.payload.package).toList(),
      isNot(contains('oxygen')),
    );

    // At some point oxygen must also be retriggered, by this can be offset by
    // the [taskDependencyRetriggerCoolOff] delay.
    await fakeTime.elapseUntil(
      () => cloud.listInstances().any((i) => i.payload.package == 'oxygen'),
      timeout: taskDependencyRetriggerCoolOff + Duration(minutes: 15),
    );

    await taskBackend.stop();

    await fakeTime.elapse(minutes: 10);
  },
      testProfile: TestProfile(
        defaultUser: 'admin@pub.dev',
        packages: [
          TestPackage(
            name: 'neon',
            versions: [TestVersion(version: '1.0.0')],
            publisher: 'example.com',
          ),
          TestPackage(
            name: 'oxygen',
            versions: [TestVersion(version: '1.0.0')],
            publisher: 'example.com',
          ),
        ],
        users: [
          TestUser(email: 'admin@pub.dev', likes: []),
        ],
      ));
}

extension<T> on Stream<T> {
  Future<bool> get isNotEmpty async {
    return !await this.isEmpty;
  }
}

extension on FakeTime {
  /// Expect [condition] to return `true` until [duration] has elapsed.
  Future<void> expectUntil(
      FutureOr<bool> Function() condition, Duration duration) async {
    try {
      await elapseUntil(() async {
        return !await condition();
      }, timeout: duration);
      fail('Condition failed before $duration expired');
    } on TimeoutException {
      return;
    }
  }
}