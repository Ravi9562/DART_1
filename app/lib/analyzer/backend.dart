// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:gcloud/datastore.dart' as datastore;
import 'package:gcloud/db.dart';
import 'package:gcloud/service_scope.dart' as ss;
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart';

import '../shared/analyzer_service.dart';
import '../shared/versions.dart';

import 'models.dart';

/// Sets the backend service.
void registerAnalysisBackend(AnalysisBackend backend) =>
    ss.register(#_analysisBackend, backend);

/// The active backend service.
AnalysisBackend get analysisBackend =>
    ss.lookup(#_analysisBackend) as AnalysisBackend;

final Logger _logger = new Logger('pub.analyzer.backend');

const Duration _freshThreshold = const Duration(hours: 12);
const Duration _identicalThreshold = const Duration(days: 7);
const Duration _regressionThreshold = const Duration(days: 45);
const Duration _obsoleteThreshold = const Duration(days: 180);

/// Datastore-related access methods for the analyzer service
class AnalysisBackend {
  final DatastoreDB db;

  AnalysisBackend(this.db);

  /// Gets the [Analysis] object from the Datastore. [version] and [analysis] is
  /// optional, when they are missing the analysis from the latest rollup will
  /// be returned.
  ///
  /// When [panaVersion] is set (and [analysis] is not), we'll try to return the
  /// latest [Analysis] instance with a matching `panaVersion` value. Note:
  /// If there is no matching `Analysis` instance with the requested version,
  /// we'll still return the latest one, regardless of its version.
  Future<AnalysisData> getAnalysis(String package,
      {String version, int analysis, String panaVersion}) async {
    final Key packageKey = db.emptyKey.append(PackageAnalysis, id: package);

    if (version == null) {
      final list = await db.lookup([packageKey]);
      final PackageAnalysis pa = list[0];
      if (pa == null) {
        _logger.info('PackageAnalysis lookup failed: no entry for $package.');
        return null;
      }
      version = pa.latestVersion;
    }

    // version was set
    final Key versionKey =
        packageKey.append(PackageVersionAnalysis, id: version);

    if (analysis == null) {
      final list = await db.lookup([versionKey]);
      final PackageVersionAnalysis pva = list[0];
      if (pva == null) {
        _logger.info(
            'PackageVersionAnalysis lookup failed: no entry for $package $version.');
        return null;
      }
      if (panaVersion == null) {
        analysis = pva.latestAnalysis;
      } else {
        final constraint = new VersionConstraint.parse('^${pva.panaVersion}');
        if (constraint.allows(new Version.parse(panaVersion))) {
          analysis = pva.latestAnalysis;
        }
      }
    }

    if (analysis == null) {
      final Query query = db.query<Analysis>(ancestorKey: versionKey)
        ..filter('panaVersion =', panaVersion);
      final List<Analysis> list = await query.run().toList();
      if (list.isNotEmpty) {
        list.sort((a, b) => -a.timestamp.compareTo(b.timestamp));
        final Analysis entry = list[0];
        return _toData(entry);
      } else {
        _logger.info(
            'Analysis lookup failed for $package $version (panaVersion=$panaVersion)');
      }
    }

    if (analysis == null) {
      return null;
    }

    // analysis was set
    final Key analysisKey = versionKey.append(Analysis, id: analysis);
    final List list = await db.lookup([analysisKey]);
    final Analysis entry = list[0];
    if (entry == null) {
      _logger.info(
          "Analysis lookup failed for $package $version (id=${analysis ?? ''}).");
      return null;
    }
    return _toData(entry);
  }

  AnalysisData _toData(Analysis entry) {
    return new AnalysisData(
        packageName: entry.packageName,
        packageVersion: entry.packageVersion,
        analysis: entry.analysis,
        timestamp: entry.timestamp,
        runtimeVersion: entry.runtimeVersion,
        panaVersion: entry.panaVersion,
        flutterVersion: entry.flutterVersion,
        analysisStatus: entry.analysisStatus,
        maintenanceScore: entry.maintenanceScore,
        analysisContent: entry.analysisJson);
  }

  /// Stores the analysis, and either creates or updates its parent
  /// [PackageAnalysis] and [PackageVersionAnalysis] records.
  ///
  /// Returns the backend status of the [Analysis].
  Future<BackendAnalysisStatus> storeAnalysis(Analysis analysis) async {
    final pvText = '${analysis.packageName} ${analysis.packageVersion}';
    // update package and version too
    final result = await db.withTransaction((Transaction tx) async {
      final incompleteRawKey = tx.db.modelDB.toDatastoreKey(analysis.key);
      final datastore.Key completeRawKey =
          (await tx.db.datastore.allocateIds([incompleteRawKey])).single;
      analysis.id = tx.db.modelDB.fromDatastoreKey(completeRawKey).id;
      final Key packageKey =
          db.emptyKey.append(PackageAnalysis, id: analysis.packageName);
      final Key packageVersionKey = packageKey.append(PackageVersionAnalysis,
          id: analysis.packageVersion);
      final List parents = await tx.lookup([packageKey, packageVersionKey]);
      PackageAnalysis package = parents[0];
      PackageVersionAnalysis version = parents[1];
      final isNewVersion = version == null;
      final isRegression = version != null &&
          version.runtimeVersion == runtimeVersion &&
          (analysisStatusLevel(version.analysisStatus) >
              analysisStatusLevel(analysis.analysisStatus));
      final hasIdenticalHash = version != null &&
          version.analysisHash != null &&
          analysis.analysisHash == version.analysisHash;

      final inserts = <Model>[];
      if (package == null) {
        package = new PackageAnalysis.fromAnalysis(analysis);
        inserts.add(package);
      } else if (package.updateWithLatest(analysis)) {
        inserts.add(package);
      }

      final Duration ageDiff = version == null
          ? null
          : analysis.timestamp.difference(version.analysisTimestamp);
      final bool preventIdentical =
          hasIdenticalHash && ageDiff < _identicalThreshold;

      if (version == null) {
        version = new PackageVersionAnalysis.fromAnalysis(analysis);
        inserts.add(version);
      } else if (preventIdentical) {
        version.analysisTimestamp = analysis.timestamp;
        inserts.add(version);
      } else if (version.updateWithLatest(analysis)) {
        inserts.add(version);
      }
      final bool wasRace =
          inserts.isEmpty && ageDiff != null && ageDiff < _freshThreshold;
      final isLatestStable = package.latestVersion == version.packageVersion;
      final bool preventRegression =
          isRegression && ageDiff != null && ageDiff < _regressionThreshold;

      if (preventRegression) {
        _logger.info('Analysis regression detected, not storing: $pvText');
        await tx.rollback();
      } else if (preventIdentical) {
        _logger
            .info('Identical analysis detected, updating timestamp: $pvText');
        // sanity check that we haven't updated the version's latest analysis
        assert(version.latestAnalysis != analysis.analysis);
        tx.queueMutations(inserts: inserts);
        await tx.commit();
      } else {
        _logger.info('Storing analysis for: $pvText');
        inserts.add(analysis);
        tx.queueMutations(inserts: inserts);
        await tx.commit();
      }
      return new BackendAnalysisStatus(wasRace, isLatestStable, isNewVersion);
    });
    return result as BackendAnalysisStatus;
  }

  /// Deletes the obsolete [Analysis] instances from Datastore. An instance is
  /// obsolete, if:
  /// - it is **not** the latest for the pana version, or
  /// - it is older than 6 months (except if it is the latest one).
  Future deleteObsoleteAnalysis(String package, String version) async {
    final pvaKey = db.emptyKey
        .append(PackageAnalysis, id: package)
        .append(PackageVersionAnalysis, id: version);
    final PackageVersionAnalysis pva = (await db.lookup([pvaKey])).single;
    if (pva == null) return;

    final DateTime threshold =
        new DateTime.now().toUtc().subtract(_obsoleteThreshold);
    final scanQuery = db.query<Analysis>(ancestorKey: pvaKey);
    final obsoleteKeys = <Key>[];

    final existingAnalysis = await scanQuery.run().toList();
    existingAnalysis.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final panaVersion2LatestAnalysis = <String, Analysis>{};
    for (Analysis analysis in existingAnalysis) {
      if (analysis.analysis == pva.latestAnalysis) {
        // Don't remove the current Analysis instance.
        continue;
      }
      final bool isTooOld = analysis.timestamp.isBefore(threshold);
      if (isTooOld) {
        obsoleteKeys.add(analysis.key);
        continue;
      }
      final Analysis prev = panaVersion2LatestAnalysis[analysis.panaVersion];
      panaVersion2LatestAnalysis[analysis.panaVersion] = analysis;
      if (prev != null) {
        obsoleteKeys.add(prev.key);
      }
    }

    // sanity check that we don't delete everything
    if (obsoleteKeys.isNotEmpty &&
        obsoleteKeys.length == existingAnalysis.length) {
      _logger.warning(
          'Inconsistency: all Analysis entries are marked as obsolete for $package $version.');
      return;
    }

    if (obsoleteKeys.isNotEmpty) {
      _logger.info('Deleting Analysis entries for $package $version: '
          '${obsoleteKeys.map((k) => k.id).join(',')}');
      await db.commit(deletes: obsoleteKeys);
    }
  }
}

class BackendAnalysisStatus {
  final bool wasRace;
  final bool isLatestStable;
  final bool isNewVersion;
  BackendAnalysisStatus(this.wasRace, this.isLatestStable, this.isNewVersion);
}
