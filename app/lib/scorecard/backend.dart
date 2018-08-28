// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:gcloud/db.dart' as db;
import 'package:gcloud/service_scope.dart' as ss;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../frontend/models.dart' show Package, PackageVersion;
import '../shared/popularity_storage.dart';
import '../shared/utils.dart';
import '../shared/versions.dart' as versions;

import 'helpers.dart';
import 'models.dart';
import 'scorecard_memcache.dart';

export 'models.dart';

final _logger = new Logger('pub.scorecard.backend');

/// Sets the active scorecard backend.
void registerScoreCardBackend(ScoreCardBackend backend) =>
    ss.register(#_scorecard_backend, backend);

/// The active job backend.
ScoreCardBackend get scoreCardBackend =>
    ss.lookup(#_scorecard_backend) as ScoreCardBackend;

class ScoreCardBackend {
  final db.DatastoreDB _db;
  ScoreCardBackend(this._db);

  Future<ScoreCardData> getScoreCardData(
    String packageName,
    String packageVersion, {
    @required bool onlyCurrent,
  }) async {
    final cached = await scoreCardMemcache.getScoreCardData(
        packageName, packageVersion, versions.runtimeVersion,
        onlyCurrent: onlyCurrent);
    if (cached != null) {
      return cached;
    }

    final key = scoreCardKey(packageName, packageVersion);
    final currentList = await _db.lookup([key]);
    if (currentList.first != null) {
      final data = (currentList.first as ScoreCard).toData();
      await scoreCardMemcache.setScoreCardData(data);
      return data;
    }

    if (onlyCurrent) {
      return null;
    }

    final query = _db.query<ScoreCard>(ancestorKey: key.parent)
      ..filter('<', versions.runtimeVersion);
    final all = await query
        .run()
        .where((sc) =>
            // sanity check to not rely entirely on the lexicographical order
            isNewer(sc.semanticRuntimeVersion, versions.semanticRuntimeVersion))
        .toList();
    if (all.isEmpty) {
      return null;
    }
    all.sort((a, b) =>
        isNewer(a.semanticRuntimeVersion, b.semanticRuntimeVersion) ? -1 : 1);
    final data = all.last.toData();
    await scoreCardMemcache.setScoreCardData(data);
    return data;
  }

  Future updateReport(
      String packageName, String packageVersion, ReportData data) async {
    final key = scoreCardKey(packageName, packageVersion)
        .append(ScoreCardReport, id: data.reportType);
    await _db.withTransaction((tx) async {
      ScoreCardReport report;
      final reportList = await tx.lookup([key]);
      report = reportList.first as ScoreCardReport;
      if (report != null) {
        _logger.info(
            'Updating report: $packageName $packageVersion ${data.reportType}.');
        report
          ..updated = new DateTime.now().toUtc()
          ..reportStatus = data.reportStatus
          ..reportJson = data.toJson();
      } else {
        _logger.info(
            'Creating new report: $packageName $packageVersion ${data.reportType}.');
        report = new ScoreCardReport.init(
          packageName: packageName,
          packageVersion: packageVersion,
          reportData: data,
        );
      }
      tx.queueMutations(inserts: [report]);
      await tx.commit();
    });
  }

  Future<Map<String, ReportData>> loadReports(
      String packageName, String packageVersion,
      {List<String> reportTypes}) async {
    reportTypes ??= [ReportType.pana, ReportType.dartdoc];
    final key = scoreCardKey(packageName, packageVersion);

    final list = await _db.lookup(reportTypes
        .map((type) => key.append(ScoreCardReport, id: type))
        .toList());

    final result = <String, ReportData>{};
    for (db.Model model in list) {
      if (model == null) continue;
      final report = model as ScoreCardReport;
      result[report.reportType] = report.reportData;
    }
    return result;
  }

  Future updateScoreCard(String packageName, String packageVersion) async {
    final key = scoreCardKey(packageName, packageVersion);
    final pAndPv = await _db.lookup([key.parent, key.parent.parent]);
    final package = pAndPv[0] as Package;
    final version = pAndPv[1] as PackageVersion;
    if (package == null || version == null) {
      throw new Exception('Unable to lookup $packageName $packageVersion.');
    }

    final reports = await loadReports(packageName, packageVersion);

    await _db.withTransaction((tx) async {
      ScoreCard scoreCard;
      final scoreCardList = await tx.lookup([key]);
      scoreCard = scoreCardList.first as ScoreCard;

      if (scoreCard == null) {
        _logger.info('Creating new ScoreCard $packageName $packageVersion.');
        scoreCard = new ScoreCard.init(
          packageName: packageName,
          packageVersion: packageVersion,
          packageCreated: package.created,
          packageVersionCreated: version.created,
        );
      } else {
        _logger.info('Updating ScoreCard $packageName $packageVersion.');
        scoreCard.updated = new DateTime.now().toUtc();
      }

      scoreCard.flags = null;
      if (package.isDiscontinued ?? false) {
        scoreCard.addFlag(PackageFlags.isDiscontinued);
      }
      if (package.doNotAdvertise ?? false) {
        scoreCard.addFlag(PackageFlags.doNotAdvertise);
      }

      scoreCard.popularityScore = popularityStorage.lookup(packageName) ?? 0.0;

      scoreCard.updateFromReports(
        panaReport: reports[ReportType.pana] as PanaReport,
        dartdocReport: reports[ReportType.dartdoc] as DartdocReport,
      );

      tx.queueMutations(inserts: [scoreCard]);
      await tx.commit();
    });

    scoreCardMemcache.invalidate(
        packageName, packageVersion, versions.runtimeVersion);
  }
}
