// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;

import 'package:gcloud/db.dart' as db;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../frontend/models.dart' show Package, PackageVersion;
import '../shared/task_scheduler.dart';
import '../shared/task_sources.dart';
import '../shared/utils.dart' show randomizeStream;

import 'backend.dart';
import 'model.dart';

export 'model.dart';

final _logger = new Logger('pub.job');
final _random = new math.Random.secure();

abstract class JobProcessor {
  final JobService service;
  final Duration lockDuration;
  final String _serviceAsString;
  JobProcessor({@required this.service, this.lockDuration})
      : _serviceAsString = jobServiceAsString(service);

  Future<JobStatus> process(Job job);

  /// Never completes.
  Future run() async {
    int sleepSeconds = 0;
    for (;;) {
      sleepSeconds = math.min(sleepSeconds + 1, 60);
      String jobDescription = '[pull]';
      try {
        final job =
            await jobBackend.lockAvailable(service, lockDuration: lockDuration);
        if (job != null) {
          jobDescription = '${job.packageName} ${job.packageVersion}';
          _logger.info('$_serviceAsString job started: $jobDescription');
          sleepSeconds = 0;

          JobStatus status;
          try {
            status = await process(job);
            status ??= JobStatus.success;
            _logger.info('$_serviceAsString job completed: $jobDescription');
          } catch (e, st) {
            status = JobStatus.failed;
            _logger.severe(
                '$_serviceAsString job error $jobDescription', e, st);
          }
          await jobBackend.complete(job, status);
        }
      } catch (e, st) {
        _logger.severe('$_serviceAsString job error $jobDescription', e, st);
      }
      await new Future.delayed(new Duration(seconds: sleepSeconds));
    }
  }
}

class JobMaintenance {
  final db.DatastoreDB _db;
  final JobService _service;
  final ShouldProcess _shouldProcess;
  JobMaintenance(this._db, this._service, this._shouldProcess);

  /// Completes when the taskStream closes.
  Future syncNotifications(Stream taskStream) async {
    await for (Task task in taskStream) {
      try {
        await _updateFromTask(task);
      } catch (e, st) {
        _logger.warning('Notification processing failed for $task', e, st);
      }
    }
  }

  Future _updateFromTask(Task task) async {
    final pKey = _db.emptyKey.append(Package, id: task.package);
    final pvKey = pKey.append(PackageVersion, id: task.version);
    final list = await _db.lookup([pKey, pvKey]);
    final Package p = list[0];
    final PackageVersion pv = list[1];
    if (p == null || pv == null) return;

    final isLatestStable = p.latestVersion == task.version;
    final updated = new DateTime.now().toUtc();
    await jobBackend.createOrUpdate(
        _service, task.package, task.version, isLatestStable, updated, true);
  }

  /// Never completes.
  Future syncDatastoreHead() async {
    final source = new DatastoreHeadTaskSource(_db, TaskSourceModel.version,
        skipHistory: true);
    final stream = source.startStreaming();
    await for (Task task in stream) {
      try {
        await _updateFromTask(task);
      } catch (e, st) {
        _logger.warning('Head sync failed for $task', e, st);
      }
    }
  }

  /// Reads the current package versions and syncs them with job entries.
  Future syncDatastoreHistory() async {
    final packages = new Map<String, String>();
    final stream = randomizeStream(_db.query(PackageVersion).run());
    await for (PackageVersion pv in stream) {
      try {
        if (!packages.containsKey(pv.package)) {
          final list = await _db.lookup([pv.packageKey]);
          final Package p = list.single;
          packages[pv.package] = p.latestVersion;
        }
        final bool isLatestStable = packages[pv.package] == pv.version;
        final shouldProcess =
            await _shouldProcess(pv.package, pv.version, pv.created);
        await jobBackend.createOrUpdate(_service, pv.package, pv.version,
            isLatestStable, pv.created, shouldProcess);
      } catch (e, st) {
        _logger.warning(
            'History sync failed for ${pv.package} ${pv.version}', e, st);
      }
    }
  }

  /// Never completes
  Future updateStates() async {
    for (;;) {
      await new Future.delayed(new Duration(minutes: 1 + _random.nextInt(10)));
      try {
        await jobBackend.unlockStaleProcessing(_service);
      } catch (e, st) {
        _logger.warning('Error unlocking stale jobs.', e, st);
      }

      await new Future.delayed(new Duration(minutes: 1 + _random.nextInt(10)));
      try {
        await jobBackend.checkIdle(_service, _shouldProcess);
      } catch (e, st) {
        _logger.warning('Error updating idle jobs.', e, st);
      }
    }
  }
}
