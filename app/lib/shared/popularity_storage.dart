// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:_popularity/popularity.dart';
import 'package:clock/clock.dart';
import 'package:gcloud/service_scope.dart' as ss;
import 'package:gcloud/storage.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../shared/cached_value.dart';
import '../shared/storage.dart';

final Logger _logger = Logger('pub.popularity');
final GZipCodec _gzip = GZipCodec();

/// Sets the popularity storage
void registerPopularityStorage(PopularityStorage storage) =>
    ss.register(#_popularityStorage, storage);

/// The active popularity storage
PopularityStorage get popularityStorage =>
    ss.lookup(#_popularityStorage) as PopularityStorage;

class PopularityStorage {
  late CachedValue<_PopularityData> _popularity;
  late final _PopularityLoader _loader;

  PopularityStorage(Bucket bucket) {
    _loader = _PopularityLoader(bucket);
    _popularity = CachedValue<_PopularityData>(
      name: 'popularity',
      interval: Duration(hours: 1),
      maxAge: Duration(days: 14),
      updateFn: () async => _loader.fetch(),
    );
  }

  DateTime? get lastFetched => _popularity.lastUpdated;
  String? get dateRange => _popularity.value?.dateRange;
  int get count => _popularity.value?.values.length ?? 0;

  double lookup(String package) =>
      _popularity.isAvailable ? _popularity.value!.values[package] ?? 0.0 : 0.0;

  int lookupAsScore(String package) => (lookup(package) * 100).round();

  Future<void> start() async {
    await _popularity.start();
  }

  Future<void> close() async {
    await _popularity.close();
  }

  // Updates popularity scores to fixed values, useful for testing.
  @visibleForTesting
  void updateValues(Map<String, double> values) {
    // ignore: invalid_use_of_visible_for_testing_member
    _popularity.setValue(
        _PopularityData(values: values, first: clock.now(), last: clock.now()));
  }
}

class _PopularityLoader {
  final Bucket bucket;
  DateTime? _fileLastUpdated;
  _PopularityData? _lastFetched;

  _PopularityLoader(this.bucket);

  String get _latestPath => PackagePopularity.popularityFileName;

  Future<_PopularityData> fetch() async {
    _logger.info(
        'Checking popularity data info: ${bucketUri(bucket, _latestPath)}');
    final info = await bucket.info(_latestPath);
    if (_fileLastUpdated != null &&
        _lastFetched != null &&
        info.updated.isAfter(_fileLastUpdated!)) {
      return _lastFetched!;
    }
    _logger.info('Loading popularity data: ${bucketUri(bucket, _latestPath)}');
    final latest = (await bucket
        .read(_latestPath)
        .transform(_gzip.decoder)
        .transform(utf8.decoder)
        .transform(json.decoder)
        .single) as Map<String, dynamic>;
    final data = _processJson(latest);
    _logger.info('Popularity updated for ${data.values.length} packages.');
    _fileLastUpdated = info.updated;
    _lastFetched = data;
    return data;
  }

  _PopularityData _processJson(Map<String, dynamic> raw) {
    final popularity = PackagePopularity.fromJson(raw);
    final List<_Entry> entries = <_Entry>[];
    popularity.items.forEach((package, totals) {
      entries.add(_Entry(package, totals.score, totals.total));
    });
    entries.sort();
    final values = <String, double>{};
    for (int i = 0; i < entries.length; i++) {
      values[entries[i].package] = i / entries.length;
    }
    return _PopularityData(
      values: values,
      first: popularity.dateFirst,
      last: popularity.dateLast,
    );
  }
}

class _PopularityData {
  final Map<String, double> values;
  final DateTime? first;
  final DateTime? last;

  _PopularityData({
    required this.values,
    required this.first,
    required this.last,
  });

  String get dateRange =>
      '${first?.toIso8601String()} - ${last?.toIso8601String()}';
}

class _Entry implements Comparable<_Entry> {
  final String package;
  final int score;
  final int total;

  _Entry(this.package, this.score, this.total);

  @override
  int compareTo(_Entry other) {
    final int x = score.compareTo(other.score);
    return x != 0 ? x : total.compareTo(other.total);
  }
}
