// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math';

import 'package:gcloud/service_scope.dart' as ss;

import '../shared/search_service.dart';

import 'text_utils.dart';

/// The [PackageIndex] registered in the current service scope.
PackageIndex get packageIndex => ss.lookup(#packageIndexService);

/// Register a new [PackageIndex] in the current service scope.
void registerPackageIndex(PackageIndex index) =>
    ss.register(#packageIndexService, index);

class SimplePackageIndex implements PackageIndex {
  final Map<String, PackageDocument> _documents = <String, PackageDocument>{};
  final TokenIndex _nameIndex = new TokenIndex();
  final TokenIndex _descrIndex = new TokenIndex();
  final TokenIndex _readmeIndex = new TokenIndex();
  DateTime _lastUpdated;
  bool _isReady = false;

  @override
  bool get isReady => _isReady;

  @override
  Future<bool> containsPackage(String package,
      {String version, Duration maxAge}) async {
    final String url = pubUrlOfPackage(package);
    final PackageDocument doc = _documents[url];
    if (doc == null) return false;
    if (version != null && doc.version != version) return false;
    if (maxAge != null &&
        (doc.timestamp == null ||
            new DateTime.now().toUtc().difference(doc.timestamp) > maxAge)) {
      return false;
    }
    return true;
  }

  @override
  Future add(PackageDocument doc) async {
    await removeUrl(doc.url);
    _documents[doc.url] = doc;
    _nameIndex.add(doc.url, doc.package);
    _descrIndex.add(doc.url, compactDescription(doc.description));
    _readmeIndex.add(doc.url, compactReadme(doc.readme));
  }

  @override
  Future addAll(Iterable<PackageDocument> documents) async {
    for (PackageDocument doc in documents) {
      await add(doc);
    }
  }

  @override
  Future removeUrl(String url) async {
    final PackageDocument doc = _documents.remove(url);
    if (doc == null) return;
    _nameIndex.removeUrl(url);
    _descrIndex.removeUrl(url);
    _readmeIndex.removeUrl(url);
  }

  @override
  Future<PackageSearchResult> search(SearchQuery query) async {
    // do text matching
    final Score textScore = _searchText(query.text, query.packagePrefix);

    // The set of urls to filter on.
    final Set<String> urls =
        textScore?.getKeys()?.toSet() ?? _documents.keys.toSet();

    // filter on package prefix
    if (query.packagePrefix != null) {
      urls.removeWhere(
        (url) => !_documents[url]
            .package
            .toLowerCase()
            .startsWith(query.packagePrefix.toLowerCase()),
      );
    }

    // filter on platform
    if (query.platformPredicate != null) {
      urls.removeWhere(
          (url) => !query.platformPredicate.matches(_documents[url].platforms));
    }

    // reduce text results if filter did remove an url
    textScore?.removeWhere((key) => !urls.contains(key));

    List<PackageScore> results;
    switch (query.order ?? SearchOrder.overall) {
      case SearchOrder.overall:
        final Score overallScore = new Score()
          ..addValues(textScore?.values, 0.85)
          ..addValues(getPopularityScore(urls), 0.10)
          ..addValues(getHealthScore(urls), 0.05);
        results = _rankWithValues(overallScore.values);
        break;
      case SearchOrder.text:
        results = _rankWithValues(textScore.values);
        break;
      case SearchOrder.updated:
        results = _rankWithComparator(urls, _compareUpdated);
        break;
      case SearchOrder.popularity:
        results = _rankWithValues(getPopularityScore(urls));
        break;
      case SearchOrder.health:
        results = _rankWithValues(getHealthScore(urls));
        break;
    }

    // bound by offset and limit
    final int totalCount = results.length;
    if (query.offset != null && query.offset > 0) {
      if (query.offset >= results.length) {
        results = <PackageScore>[];
      } else {
        results = results.sublist(query.offset);
      }
    }
    if (query.limit != null && results.length > query.limit) {
      results = results.sublist(0, query.limit);
    }

    return new PackageSearchResult(
      totalCount: totalCount,
      indexUpdated: _lastUpdated.toIso8601String(),
      packages: results,
    );
  }

  @override
  Future merge() async {
    _isReady = true;
    _lastUpdated = new DateTime.now().toUtc();
  }

  // visible for testing only
  Map<String, double> getHealthScore(Iterable<String> urls) {
    return new Map.fromIterable(
      urls,
      value: (String url) => (_documents[url].health ?? 0.0) * 100,
    );
  }

  // visible for testing only
  Map<String, double> getPopularityScore(Iterable<String> urls) {
    return new Map.fromIterable(
      urls,
      value: (String url) => _documents[url].popularity * 100,
    );
  }

  Score _searchText(String text, String packagePrefix) {
    if (text != null && text.isNotEmpty) {
      final Score textScore = new Score()
        ..addValues(_nameIndex.search(text), 0.82)
        ..addValues(_descrIndex.search(text), 0.12)
        ..addValues(_readmeIndex.search(text), 0.06);
      // removes scores that are less than 5% of the best
      textScore.removeLowScores(0.05);
      // removes scores that are low
      textScore.removeWhere((url) => textScore.values[url] < 1.0);
      return textScore;
    }
    return null;
  }

  List<PackageScore> _rankWithValues(Map<String, double> values) {
    final List<PackageScore> list = values.keys
        .map((url) => new PackageScore(
              url: url,
              package: _documents[url].package,
              score: values[url],
            ))
        .toList();
    list.sort((a, b) {
      final int scoreCompare = -a.score.compareTo(b.score);
      if (scoreCompare != 0) return scoreCompare;
      // if two packages got the same score, order by last updated
      return _compareUpdated(_documents[a.url], _documents[b.url]);
    });
    return list;
  }

  List<PackageScore> _rankWithComparator(
      Set<String> urls, int compare(PackageDocument a, PackageDocument b)) {
    final List<PackageScore> list = urls
        .map((url) =>
            new PackageScore(url: url, package: _documents[url].package))
        .toList();
    list.sort((a, b) => compare(_documents[a.url], _documents[b.url]));
    return list;
  }

  int _compareUpdated(PackageDocument a, PackageDocument b) {
    if (a.updated == null) return -1;
    if (b.updated == null) return 1;
    return -a.updated.compareTo(b.updated);
  }
}

class Score {
  final Map<String, double> values = <String, double>{};

  Iterable<String> getKeys() => values.keys;

  void addValues(Map<String, double> newValues, double weight) {
    if (newValues == null) return;
    newValues.forEach((String key, double score) {
      if (score != null) {
        final double prev = values[key] ?? 0.0;
        values[key] = prev + score * weight;
      }
    });
  }

  void removeWhere(bool keyCondition(String key)) {
    final Set<String> keysToRemove = values.keys.where(keyCondition).toSet();
    keysToRemove.forEach(values.remove);
  }

  void removeLowScores(double fraction) {
    final double maxValue = values.values.fold(0.0, max);
    final double cutoff = maxValue * fraction;
    removeWhere((key) => values[key] < cutoff);
  }
}

class TokenIndex {
  final Map<String, Set<String>> _inverseUrls = <String, Set<String>>{};
  final Map<String, double> _weights = <String, double>{};

  /// The number of tokens stored in the index.
  int get tokenCount => _inverseUrls.length;

  void add(String url, String text) {
    final Set<String> tokens = _tokenize(text);
    if (tokens == null || tokens.isEmpty) return;
    double sumWeight = 0.0;
    for (String token in tokens) {
      final Set<String> set = _inverseUrls.putIfAbsent(token, () => new Set());
      set.add(url);
      sumWeight += _tokenWeight(token);
    }
    _weights[url] = sumWeight;
  }

  void removeUrl(String url) {
    _weights.remove(url);
    final List<String> removeKeys = [];
    _inverseUrls.forEach((String key, Set<String> set) {
      set.remove(url);
      if (set.isEmpty) removeKeys.add(key);
    });
    removeKeys.forEach(_inverseUrls.remove);
  }

  // A TF-IDF-like scoring, with more weight for longer terms.
  Map<String, double> search(String text) {
    final Set<String> tokens = _tokenize(text);
    if (tokens == null || tokens.isEmpty) return null;
    double sumWeight = 0.0;
    final Map<String, double> counts = <String, double>{};
    for (String token in tokens) {
      final double tokenWeight = _tokenWeight(token);
      sumWeight += tokenWeight;

      final Set<String> set = _inverseUrls[token];
      if (set == null || set.isEmpty) continue;

      for (String url in set) {
        final double prevValue = counts[url] ?? 0.0;
        counts[url] = prevValue + tokenWeight;
      }
    }
    for (String url in counts.keys.toList()) {
      final double current = counts[url];
      counts[url] = 100.0 * (current / _weights[url]) * (current / sumWeight);
    }
    return counts;
  }

  // The longer the token, the more importance it has.
  // Length -> Weight
  // 1 ->  1 (Length * Length)
  // 2 ->  4 (Length * Length)
  // 3 ->  9 (Length * Length)
  // 4 -> 16 (Length * Length)
  // 5 -> 20 (Length * 4)
  // 6 -> 24 (Length * 4)
  // 7 -> 28 (Length * 4)
  // 8 -> 32 (Length * 4)
  double _tokenWeight(String token) =>
      (token.length * min(token.length, 4)).toDouble();
}

const int minNgram = 1;
const int maxNgram = 4;
const int maxWordLength = 80;

Set<String> _tokenize(String originalText) {
  if (originalText == null || originalText.isEmpty) return null;
  final Set<String> tokens = new Set();

  void addAllPrefixes(String phrase) {
    for (int i = maxNgram + 1; i < phrase.length; i++) {
      tokens.add(phrase.substring(0, i));
    }
    tokens.add(phrase);
  }

  for (String word in splitForIndexing(originalText)) {
    if (word.length > maxWordLength) word = word.substring(0, maxWordLength);

    final String normalizedWord = normalizeBeforeIndexing(word);
    if (normalizedWord.isEmpty) continue;

    for (int ngramLength = minNgram; ngramLength <= maxNgram; ngramLength++) {
      if (normalizedWord.length <= ngramLength) {
        tokens.add(normalizedWord);
      } else {
        for (int i = 0; i <= normalizedWord.length - ngramLength; i++) {
          tokens.add(normalizedWord.substring(i, i + ngramLength));
        }
      }
    }
    if (word.length <= maxNgram) continue; // ngrams covered everything

    // add all prefixes for better relevancy on longer phrases
    addAllPrefixes(normalizedWord);

    // scan for CamelCase phrases and index Case
    bool prevLower = _isLower(word[0]);
    for (int i = 1; i < word.length; i++) {
      final bool lower = _isLower(word[i]);
      if (!lower && prevLower) {
        final String part = word.substring(i);
        final String normalizedPart = normalizeBeforeIndexing(part);
        addAllPrefixes(normalizedPart);
      }
      prevLower = lower;
    }
  }
  return tokens;
}

bool _isLower(String c) => c.toLowerCase() == c;
