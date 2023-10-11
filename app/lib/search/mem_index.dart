// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math' as math;

import 'package:_pub_shared/search/search_form.dart';
import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../shared/utils.dart' show boundedList;
import 'models.dart';
import 'search_service.dart';
import 'text_utils.dart';
import 'token_index.dart';

final _logger = Logger('search.mem_index');
final _textSearchTimeout = Duration(milliseconds: 500);

class InMemoryPackageIndex {
  final Map<String, PackageDocument> _packages = <String, PackageDocument>{};
  final _packageNameIndex = PackageNameIndex();
  final TokenIndex _descrIndex = TokenIndex();
  final TokenIndex _readmeIndex = TokenIndex();
  final TokenIndex _apiSymbolIndex = TokenIndex();
  late final List<PackageHit> _createdOrderedHits;
  late final List<PackageHit> _updatedOrderedHits;
  late final List<PackageHit> _popularityOrderedHits;
  late final List<PackageHit> _likesOrderedHits;
  late final List<PackageHit> _pointsOrderedHits;

  late final DateTime _lastUpdated;

  InMemoryPackageIndex({
    required Iterable<PackageDocument> documents,
  }) {
    for (final doc in documents) {
      _addPackage(doc);
    }
    // update like scores only if they were not set (should happen only in local tests)
    if (_packages.values.any((e) => e.likeScore == null)) {
      _packages.values.updateLikeScores();
    }
    _lastUpdated = clock.now().toUtc();
    _createdOrderedHits = _rankWithComparator(_compareCreated);
    _updatedOrderedHits = _rankWithComparator(_compareUpdated);
    _popularityOrderedHits = _rankWithComparator(_comparePopularity,
        score: (doc) => doc.popularityScore ?? 0);
    _likesOrderedHits = _rankWithComparator(_compareLikes,
        score: (doc) => doc.likeCount.toDouble());
    _pointsOrderedHits = _rankWithComparator(_comparePoints,
        score: (doc) => doc.grantedPoints.toDouble());
  }

  IndexInfo indexInfo() {
    return IndexInfo(
      isReady: true,
      packageCount: _packages.length,
      lastUpdated: _lastUpdated,
    );
  }

  void _addPackage(PackageDocument doc) {
    _packages[doc.package] = doc;
    _packageNameIndex.add(doc.package);
    _descrIndex.add(doc.package, doc.description);
    _readmeIndex.add(doc.package, doc.readme);

    for (ApiDocPage page in doc.apiDocPages ?? const []) {
      final pageId = _apiDocPageId(doc.package, page);
      if (page.symbols != null && page.symbols!.isNotEmpty) {
        _apiSymbolIndex.add(pageId, page.symbols!.join(' '));
      }
    }
  }

  PackageSearchResult search(ServiceSearchQuery query) {
    final packages = Set<String>.of(_packages.keys);

    // filter on package prefix
    if (query.parsedQuery.packagePrefix != null) {
      final String prefix = query.parsedQuery.packagePrefix!.toLowerCase();
      packages.removeWhere(
        (package) =>
            !_packages[package]!.package.toLowerCase().startsWith(prefix),
      );
    }

    // filter on tags
    final combinedTagsPredicate =
        query.tagsPredicate.appendPredicate(query.parsedQuery.tagsPredicate);
    if (combinedTagsPredicate.isNotEmpty) {
      packages.retainWhere((package) =>
          combinedTagsPredicate.matches(_packages[package]!.tagsForLookup));
    }

    // filter on dependency
    if (query.parsedQuery.hasAnyDependency) {
      packages.removeWhere((package) {
        final doc = _packages[package]!;
        if (doc.dependencies.isEmpty) return true;
        for (String dependency in query.parsedQuery.allDependencies) {
          if (!doc.dependencies.containsKey(dependency)) return true;
        }
        for (String dependency in query.parsedQuery.refDependencies) {
          final type = doc.dependencies[dependency];
          if (type == null || type == DependencyTypes.transitive) return true;
        }
        return false;
      });
    }

    // filter on points
    if (query.minPoints != null && query.minPoints! > 0) {
      packages.removeWhere((package) {
        final doc = _packages[package]!;
        return doc.grantedPoints < query.minPoints!;
      });
    }

    // filter on updatedInDays
    if (query.updatedInDays != null && query.updatedInDays! > 0) {
      final threshold =
          Duration(days: query.updatedInDays!, hours: 11, minutes: 59);
      final now = clock.now();
      packages.removeWhere((package) {
        final doc = _packages[package]!;
        final diff = now.difference(doc.updated!);
        return diff > threshold;
      });
    }

    // do text matching
    final textResults = _searchText(packages, query.parsedQuery.text);

    // filter packages that doesn't match text query
    if (textResults != null) {
      final keys = textResults.pkgScore.getKeys();
      packages.removeWhere((x) => !keys.contains(x));
    }

    late List<PackageHit> packageHits;
    switch (query.effectiveOrder ?? SearchOrder.top) {
      case SearchOrder.top:
        final scores = <Score>[
          _getOverallScore(packages),
          if (textResults != null) textResults.pkgScore,
        ];
        final overallScore = Score.multiply(scores);
        // If the search hits have an exact name match, we move it to the front of the result list.
        final parsedQueryText = query.parsedQuery.text;
        final priorityPackageName =
            packages.contains(parsedQueryText ?? '') ? parsedQueryText : null;
        packageHits = _rankWithValues(
          overallScore.getValues(),
          priorityPackageName: priorityPackageName,
        );
        break;
      case SearchOrder.text:
        final score = textResults?.pkgScore ?? Score.empty();
        packageHits = _rankWithValues(score.getValues());
        break;
      case SearchOrder.created:
        packageHits = _createdOrderedHits.whereInSet(packages);
        break;
      case SearchOrder.updated:
        packageHits = _updatedOrderedHits.whereInSet(packages);
        break;
      case SearchOrder.popularity:
        packageHits = _popularityOrderedHits.whereInSet(packages);
        break;
      case SearchOrder.like:
        packageHits = _likesOrderedHits.whereInSet(packages);
        break;
      case SearchOrder.points:
        packageHits = _pointsOrderedHits.whereInSet(packages);
        break;
    }

    // bound by offset and limit (or randomize items)
    final totalCount = packageHits.length;
    packageHits =
        boundedList(packageHits, offset: query.offset, limit: query.limit);

    if (textResults != null && textResults.topApiPages.isNotEmpty) {
      packageHits = packageHits.map((ps) {
        final apiPages = textResults.topApiPages[ps.package]
            // TODO(https://github.com/dart-lang/pub-dev/issues/7106): extract title for the page
            ?.map((MapEntry<String, double> e) =>
                ApiPageRef(path: _apiDocPath(e.key)))
            .toList();
        return ps.change(apiPages: apiPages);
      }).toList();
    }

    return PackageSearchResult(
      timestamp: clock.now().toUtc(),
      totalCount: totalCount,
      packageHits: packageHits,
    );
  }

  Score _getOverallScore(Iterable<String> packages) {
    final values = Map<String, double>.fromEntries(packages.map((package) {
      final doc = _packages[package]!;
      final downloadScore = doc.popularityScore ?? 0.0;
      final likeScore = doc.likeScore ?? 0.0;
      final popularity = (downloadScore + likeScore) / 2;
      final points = doc.grantedPoints / math.max(1, doc.maxPoints);
      final overall = popularity * 0.5 + points * 0.5;
      // don't multiply with zero.
      return MapEntry(package, 0.4 + 0.6 * overall);
    }));
    return Score(values);
  }

  _TextResults? _searchText(Set<String> packages, String? text) {
    final sw = Stopwatch()..start();
    if (text != null && text.isNotEmpty) {
      final words = splitForQuery(text);
      if (words.isEmpty) {
        return _TextResults(Score.empty(), {});
      }

      bool aborted = false;

      bool checkAborted() {
        if (!aborted && sw.elapsed > _textSearchTimeout) {
          aborted = true;
          _logger.info(
              '[pub-aborted-search-query] Aborted text search after ${sw.elapsedMilliseconds} ms.');
        }
        return aborted;
      }

      // Multiple words are scored separately, and then the individual scores
      // are multiplied. We can use a package filter that is applied after each
      // word to reduce the scope of the later words based on the previous results.
      // We cannot update the main `packages` variable yet, as the dartdoc API
      // symbols are added on top of the core results, and `packages` is used
      // there too.
      final coreScores = <Score>[];
      var wordScopedPackages = packages;
      for (final word in words) {
        final nameScore =
            _packageNameIndex.searchWord(word, packages: wordScopedPackages);
        final descr = _descrIndex
            .searchWords([word], weight: 0.90, limitToIds: wordScopedPackages);
        final readme = _readmeIndex
            .searchWords([word], weight: 0.75, limitToIds: wordScopedPackages);
        final score = Score.max([nameScore, descr, readme]);
        coreScores.add(score);
        // don't update if the query is single-word
        if (words.length > 1) {
          wordScopedPackages = score.getKeys();
          if (wordScopedPackages.isEmpty) {
            break;
          }
        }
      }

      final core = Score.multiply(coreScores);

      var symbolPages = Score.empty();
      if (!checkAborted()) {
        symbolPages = _apiSymbolIndex.searchWords(words, weight: 0.70);
      }

      final apiPackages = <String, double>{};
      final topApiPages = <String, List<MapEntry<String, double>>>{};
      const maxApiPageCount = 2;
      for (final entry in symbolPages.getValues().entries) {
        final pkg = _apiDocPkg(entry.key);
        if (!packages.contains(pkg)) continue;

        // skip if the previously found pages are better than the current one
        final pages = topApiPages.putIfAbsent(pkg, () => []);
        if (pages.length >= maxApiPageCount && pages.last.value > entry.value) {
          continue;
        }

        // update the top api packages score
        apiPackages[pkg] = math.max(entry.value, apiPackages[pkg] ?? 0.0);

        // add the page and re-sort the current results
        pages.add(entry);
        if (pages.length > 1) {
          pages.sort((a, b) => -a.value.compareTo(b.value));
        }
        // keep the results limited to the max count
        if (pages.length > maxApiPageCount) {
          pages.removeLast();
        }
      }

      final apiPkgScore = Score(apiPackages);
      var score = Score.max([core, apiPkgScore])
          .project(packages)
          .removeLowValues(fraction: 0.2, minValue: 0.01);

      // filter results based on exact phrases
      final phrases = extractExactPhrases(text);
      if (!aborted && phrases.isNotEmpty) {
        final matched = <String, double>{};
        for (String package in score.getKeys()) {
          final doc = _packages[package]!;
          final bool matchedAllPhrases = phrases.every((phrase) =>
              doc.package.contains(phrase) ||
              doc.description!.contains(phrase) ||
              doc.readme!.contains(phrase));
          if (matchedAllPhrases) {
            matched[package] = score[package];
          }
        }
        score = Score(matched);
      }

      return _TextResults(score, topApiPages);
    }
    return null;
  }

  List<PackageHit> _rankWithValues(
    Map<String, double> values, {
    String? priorityPackageName,
  }) {
    final list = values.entries
        .map((e) => PackageHit(package: e.key, score: e.value))
        .toList();
    list.sort((a, b) {
      if (a.package == priorityPackageName) return -1;
      if (b.package == priorityPackageName) return 1;
      final int scoreCompare = -a.score!.compareTo(b.score!);
      if (scoreCompare != 0) return scoreCompare;
      // if two packages got the same score, order by last updated
      return _compareUpdated(_packages[a.package]!, _packages[b.package]!);
    });
    return list;
  }

  List<PackageHit> _rankWithComparator(
    int Function(PackageDocument a, PackageDocument b) compare, {
    double Function(PackageDocument doc)? score,
  }) {
    final list = _packages.values
        .map((doc) => PackageHit(
            package: doc.package, score: score == null ? null : score(doc)))
        .toList();
    list.sort((a, b) => compare(_packages[a.package]!, _packages[b.package]!));
    return list;
  }

  int _compareCreated(PackageDocument a, PackageDocument b) {
    if (a.created == null) return 1;
    if (b.created == null) return -1;
    return -a.created!.compareTo(b.created!);
  }

  int _compareUpdated(PackageDocument a, PackageDocument b) {
    if (a.updated == null) return 1;
    if (b.updated == null) return -1;
    return -a.updated!.compareTo(b.updated!);
  }

  int _comparePopularity(PackageDocument a, PackageDocument b) {
    final x = -(a.popularityScore ?? 0.0).compareTo(b.popularityScore ?? 0.0);
    if (x != 0) return x;
    return _compareUpdated(a, b);
  }

  int _compareLikes(PackageDocument a, PackageDocument b) {
    final x = -a.likeCount.compareTo(b.likeCount);
    if (x != 0) return x;
    return _compareUpdated(a, b);
  }

  int _comparePoints(PackageDocument a, PackageDocument b) {
    final x = -a.grantedPoints.compareTo(b.grantedPoints);
    if (x != 0) return x;
    return _compareUpdated(a, b);
  }

  String _apiDocPageId(String package, ApiDocPage page) {
    return '$package::${page.relativePath}';
  }

  String _apiDocPkg(String id) {
    return id.split('::').first;
  }

  String _apiDocPath(String id) {
    return id.split('::').last;
  }
}

class _TextResults {
  final Score pkgScore;
  final Map<String, List<MapEntry<String, double>>> topApiPages;

  _TextResults(this.pkgScore, this.topApiPages);
}

/// A simple (non-inverted) index designed for package name lookup.
@visibleForTesting
class PackageNameIndex {
  final _data = <String, _PkgNameData>{};

  /// Maps package name to a reduced form of the name:
  /// the same character parts, but without `-`.
  String _collapseName(String package) =>
      package.replaceAll('_', '').toLowerCase();

  void addAll(Iterable<String> packages) {
    for (final package in packages) {
      add(package);
    }
  }

  /// Add a new [package] to the index.
  void add(String package) {
    _data.putIfAbsent(package, () {
      final collapsed = _collapseName(package);
      return _PkgNameData(collapsed, trigrams(collapsed).toSet());
    });
  }

  /// Search [text] and return the matching packages with scores.
  Score search(String text) {
    return Score.multiply(splitForQuery(text).map(searchWord).toList());
  }

  /// Search using the parsed [word] and return the match packages with scores.
  Score searchWord(String word, {Set<String>? packages}) {
    final pkgNamesToCheck = packages ?? _data.keys;
    final values = <String, double>{};
    final singularWord = word.length <= 3 || !word.endsWith('s')
        ? word
        : word.substring(0, word.length - 1);
    final collapsedWord = _collapseName(singularWord);
    final parts =
        collapsedWord.length <= 3 ? [collapsedWord] : trigrams(collapsedWord);
    for (final pkg in pkgNamesToCheck) {
      final entry = _data[pkg];
      if (entry == null) {
        continue;
      }
      if (entry.collapsed.contains(collapsedWord)) {
        values[pkg] = 1.0;
        continue;
      }
      var matched = 0;
      for (final part in parts) {
        if (entry.trigrams.contains(part)) {
          matched++;
        }
      }
      if (matched > 0) {
        values[pkg] = matched / parts.length;
      }
    }
    return Score(values).removeLowValues(fraction: 0.5, minValue: 0.5);
  }
}

class _PkgNameData {
  final String collapsed;
  final Set<String> trigrams;

  _PkgNameData(this.collapsed, this.trigrams);
}

extension on List<PackageHit> {
  List<PackageHit> whereInSet(Set<String> packages) {
    return where((hit) => packages.contains(hit.package)).toList();
  }
}
