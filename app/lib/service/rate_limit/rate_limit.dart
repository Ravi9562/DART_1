// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:pub_dev/audit/backend.dart';

import '../../account/agent.dart';
import '../../audit/models.dart';
import '../../shared/configuration.dart';
import '../../shared/exceptions.dart';
import '../../shared/redis_cache.dart';

/// Verifies if the current package upload has a rate limit and throws
/// if the limit has been exceeded.
Future<void> verifyPackageUploadRateLimit({
  required AuthenticatedAgent agent,
  required String package,
}) async {
  final operation = AuditLogRecordKind.packagePublished;
  if (agent.email != null) {
    await _verifyRateLimit(
      rateLimit: _getRateLimit(operation, RateLimitScope.user),
      dataFilters: {'email': agent.email!},
    );
  }

  await _verifyRateLimit(
    rateLimit: _getRateLimit(operation, RateLimitScope.package),
    package: package,
  );
}

RateLimit? _getRateLimit(String operation, RateLimitScope scope) {
  return activeConfiguration.rateLimits?.firstWhereOrNull(
    (r) => r.operation == operation && r.scope == scope,
  );
}

Future<void> _verifyRateLimit({
  required RateLimit? rateLimit,
  Map<String, String>? dataFilters,
  String? package,
}) async {
  if (rateLimit == null) {
    return;
  }
  if (rateLimit.burst == null &&
      rateLimit.hourly == null &&
      rateLimit.daily == null) {
    return;
  }

  final cacheKeyParts = [
    rateLimit.operation,
    rateLimit.scope.name,
    if (package != null) 'package-$package',
    ...?dataFilters?.entries.map((e) => [e.key, e.value].join('-')),
  ];
  final entryKey = Uri(pathSegments: cacheKeyParts).toString();

  final auditEntriesFromLastDay = await auditBackend.getEntriesFromLastDay();

  Future<void> check({
    required Duration window,
    required int? maxCount,
    required String windowAsText,
  }) async {
    if (maxCount == null || maxCount <= 0) {
      return;
    }

    final entry = cache.rateLimitUntil(entryKey: entryKey, window: window);
    final current = await entry.get();
    if (current != null && current.isAfter(clock.now())) {
      throw RateLimitException(
        maxCount: maxCount,
        windowAsText: windowAsText,
      );
    }

    final now = clock.now().toUtc();
    final windowStart = now.subtract(window);
    final relevantEntries = auditEntriesFromLastDay
        .where((e) => e.kind == rateLimit.operation)
        .where((e) => e.created!.isAfter(windowStart))
        .where((e) => _containsPackage(e.packages, package))
        .where((e) => _containsData(e.data, dataFilters))
        .toList();

    if (relevantEntries.length >= maxCount) {
      final firstTimestamp = relevantEntries
          .map((e) => e.created!)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      await entry.set(firstTimestamp.add(window));
      throw RateLimitException(
        maxCount: maxCount,
        windowAsText: windowAsText,
      );
    }
  }

  await check(
    window: Duration(minutes: 2),
    maxCount: rateLimit.burst,
    windowAsText: 'last few minutes',
  );
  await check(
    window: Duration(hours: 1),
    maxCount: rateLimit.hourly,
    windowAsText: 'last hour',
  );
  await check(
    window: Duration(days: 1),
    maxCount: rateLimit.daily,
    windowAsText: 'last day',
  );
}

bool _containsPackage(
  List<String>? packages,
  String? package,
) {
  if (packages == null || packages.isEmpty) {
    return false;
  }
  if (package == null) {
    return false;
  }
  return packages.contains(package);
}

bool _containsData(
  Map<String, dynamic>? data,
  Map<String, String>? filters,
) {
  if (data == null) {
    return false;
  }
  if (filters == null || filters.isEmpty) {
    return true;
  }
  for (final entry in filters.entries) {
    if (data[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
