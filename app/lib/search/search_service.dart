// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math' show max;

import 'package:json_annotation/json_annotation.dart';

part 'search_service.g.dart';

const int _minSearchLimit = 10;
const int searchIndexNotReadyCode = 600;
const String searchIndexNotReadyText = 'Not ready yet.';

/// The number of packages we are going to display on a search page.
const int resultsPerPage = 10;

/// The number of page links we display, e.g. on page 10, we display direct
/// links from page 5 to page 15.
const int maxPages = 10;

/// Package search index and lookup.
abstract class PackageIndex {
  bool get isReady;
  Future<void> addPackage(PackageDocument doc);
  Future<void> addPackages(Iterable<PackageDocument> documents);
  Future<void> removePackage(String package);
  Future<void> merge();
  Future<PackageSearchResult> search(SearchQuery query);
  Map<String, dynamic> get debugInfo;
}

/// A summary information about a package that goes into the search index.
///
/// It is also part of the data structure returned by a search query, except for
/// the [readme] and [popularity] fields, which are excluded when returning the
/// results.
@JsonSerializable()
class PackageDocument {
  final String package;
  final String version;
  final String devVersion;
  final String description;
  final DateTime created;
  final DateTime updated;
  final String readme;
  final bool isDiscontinued;
  final bool doNotAdvertise;

  /// True, if this package only supports 1.x (ie. package is 2.0 incompatible)
  final bool supportsOnlyLegacySdk;

  final List<String> platforms;

  final List<String> tags;

  final double health;
  final double popularity;
  final double maintenance;

  final Map<String, String> dependencies;

  /// The publisher id of the package
  final String publisherId;

  /// The current uploader emails of the package.
  final List<String> uploaderEmails;

  final List<ApiDocPage> apiDocPages;

  /// The creation timestamp of this document.
  final DateTime timestamp;

  PackageDocument({
    this.package,
    this.version,
    this.devVersion,
    this.description,
    this.created,
    this.updated,
    this.readme = '',
    this.isDiscontinued = false,
    this.doNotAdvertise = false,
    this.supportsOnlyLegacySdk = false,
    this.platforms = const [],
    List<String> tags,
    this.health = 0,
    this.popularity = 0,
    this.maintenance = 0,
    this.dependencies = const {},
    this.publisherId,
    this.uploaderEmails = const [],
    this.apiDocPages = const [],
    DateTime timestamp,
  })  : tags = tags ?? const <String>[],
        timestamp = timestamp ?? DateTime.now();

  factory PackageDocument.fromJson(Map<String, dynamic> json) =>
      _$PackageDocumentFromJson(json);

  PackageDocument intern(String internFn(String value)) {
    return PackageDocument(
      package: internFn(package),
      version: version,
      devVersion: devVersion,
      description: description,
      created: created,
      updated: updated,
      readme: readme,
      isDiscontinued: isDiscontinued,
      doNotAdvertise: doNotAdvertise,
      supportsOnlyLegacySdk: supportsOnlyLegacySdk,
      platforms: platforms?.map(internFn)?.toList(),
      tags: tags.map(internFn).toList(),
      health: health,
      popularity: popularity,
      maintenance: maintenance,
      dependencies: dependencies == null
          ? null
          : Map.fromIterable(
              dependencies.keys,
              key: (key) => internFn(key as String),
              value: (key) => internFn(dependencies[key]),
            ),
      publisherId: internFn(publisherId),
      uploaderEmails: uploaderEmails?.map(internFn)?.toList(),
      apiDocPages: apiDocPages?.map((p) => p.intern(internFn))?.toList(),
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() => _$PackageDocumentToJson(this);
}

/// A reference to an API doc page
@JsonSerializable()
class ApiDocPage {
  final String relativePath;
  final List<String> symbols;
  final List<String> textBlocks;

  ApiDocPage({this.relativePath, this.symbols, this.textBlocks});

  factory ApiDocPage.fromJson(Map<String, dynamic> json) =>
      _$ApiDocPageFromJson(json);

  ApiDocPage intern(String internFn(String value)) {
    return ApiDocPage(
      relativePath: internFn(relativePath),
      symbols: symbols?.map(internFn)?.toList(),
      textBlocks: textBlocks,
    );
  }

  Map<String, dynamic> toJson() => _$ApiDocPageToJson(this);
}

/// How search results should be ordered.
enum SearchOrder {
  /// Search score should be a weighted value of [text], [popularity], [health]
  /// and [maintenance], ordered decreasing.
  top,

  /// Search score should depend only on text match similarity, ordered
  /// decreasing.
  text,

  /// Search order should be in decreasing last package creation time.
  created,

  /// Search order should be in decreasing last package updated time.
  updated,

  /// Search order should be in decreasing popularity score.
  popularity,

  /// Search order should be in decreasing health score.
  health,

  /// Search order should be in decreasing maintenance score.
  maintenance,
}

/// Returns null if [value] is not a recognized search order.
SearchOrder parseSearchOrder(String value) {
  if (value == null) {
    return null;
  }
  switch (value) {
    case 'top':
      return SearchOrder.top;
    case 'text':
      return SearchOrder.text;
    case 'created':
      return SearchOrder.created;
    case 'updated':
      return SearchOrder.updated;
    case 'popularity':
      return SearchOrder.popularity;
    case 'health':
      return SearchOrder.health;
    case 'maintenance':
      return SearchOrder.maintenance;
  }
  return null;
}

String serializeSearchOrder(SearchOrder order) {
  if (order == null) return null;
  return order.toString().split('.').last;
}

final RegExp _whitespacesRegExp = RegExp(r'\s+');
final RegExp _packageRegexp =
    RegExp('package:([_a-z0-9]+)', caseSensitive: false);
final RegExp _publisherRegexp =
    RegExp(r'publisher:([_a-z0-9\.]+)', caseSensitive: false);
final RegExp _emailRegexp =
    RegExp(r'email:([_a-z0-9\@\-\.\+]+)', caseSensitive: false);
final RegExp _refDependencyRegExp =
    RegExp('dependency:([_a-z0-9]+)', caseSensitive: false);
final RegExp _allDependencyRegExp =
    RegExp(r'dependency\*:([_a-z0-9]+)', caseSensitive: false);

class SearchQuery {
  final String query;
  final ParsedQuery parsedQuery;
  final String platform;

  final TagsPredicate tagsPredicate;

  /// The query will match packages where the owners of the package have
  /// non-empty intersection with the provided list of owners.
  ///
  /// Values of this list can be email addresses (usually a single on) or
  /// publisher ids (may be multiple).
  final List<String> uploaderOrPublishers;

  final String publisherId;
  final SearchOrder order;
  final int offset;
  final int limit;
  final bool isAd;
  final bool isApiEnabled;

  /// True, if packages which only support dart 1.x should be included.
  final bool includeLegacy;

  SearchQuery._({
    this.query,
    String platform,
    this.tagsPredicate,
    List<String> uploaderOrPublishers,
    String publisherId,
    this.order,
    this.offset,
    this.limit,
    this.isAd,
    this.isApiEnabled,
    this.includeLegacy,
  })  : parsedQuery = ParsedQuery._parse(query),
        platform = (platform == null || platform.isEmpty) ? null : platform,
        uploaderOrPublishers =
            (uploaderOrPublishers == null || uploaderOrPublishers.isEmpty)
                ? null
                : uploaderOrPublishers,
        publisherId =
            (publisherId == null || publisherId.isEmpty) ? null : publisherId;

  factory SearchQuery.parse({
    String query,
    String platform,
    TagsPredicate tagsPredicate,
    List<String> uploaderOrPublishers,
    String publisherId,
    SearchOrder order,
    int offset = 0,
    int limit = 10,
    bool isAd = false,
    bool apiEnabled = true,
    bool includeLegacy = false,
  }) {
    final String q =
        query != null && query.trim().isNotEmpty ? query.trim() : null;
    return SearchQuery._(
      query: q,
      platform: platform,
      tagsPredicate: tagsPredicate,
      uploaderOrPublishers: uploaderOrPublishers,
      publisherId: publisherId,
      order: order,
      offset: offset,
      limit: limit,
      isAd: isAd,
      isApiEnabled: apiEnabled,
      includeLegacy: includeLegacy,
    );
  }

  factory SearchQuery.fromServiceUrl(Uri uri) {
    final String q = uri.queryParameters['q'];
    final String platform =
        uri.queryParameters['platform'] ?? uri.queryParameters['platforms'];
    final tagsPredicate =
        TagsPredicate.parseQueryValues(uri.queryParametersAll['tags']);
    final uploaderOrPublishers = uri.queryParametersAll['uploaderOrPublishers'];
    final publisherId = uri.queryParameters['publisherId'];
    final String orderValue = uri.queryParameters['order'];
    final SearchOrder order = parseSearchOrder(orderValue);

    final offset = int.tryParse(uri.queryParameters['offset'] ?? '0') ?? 0;
    final limit = int.tryParse(uri.queryParameters['limit'] ?? '0') ?? 0;

    return SearchQuery.parse(
      query: q,
      platform: platform,
      tagsPredicate: tagsPredicate,
      uploaderOrPublishers: uploaderOrPublishers,
      publisherId: publisherId,
      order: order,
      offset: max(0, offset),
      limit: max(_minSearchLimit, limit),
      isAd: uri.queryParameters['ad'] == '1',
      apiEnabled: uri.queryParameters['api'] != '0',
      includeLegacy: uri.queryParameters['legacy'] == '1',
    );
  }

  SearchQuery change({
    String query,
    String platform,
    TagsPredicate tagsPredicate,
    List<String> uploaderOrPublishers,
    String publisherId,
    SearchOrder order,
    int offset,
    int limit,
    bool isAd,
    bool apiEnabled,
    bool includeLegacy,
  }) {
    return SearchQuery._(
      query: query ?? this.query,
      platform: platform ?? this.platform,
      tagsPredicate: tagsPredicate,
      uploaderOrPublishers: uploaderOrPublishers ?? this.uploaderOrPublishers,
      publisherId: publisherId ?? this.publisherId,
      order: order ?? this.order,
      offset: offset ?? this.offset,
      limit: limit ?? this.limit,
      isAd: isAd ?? this.isAd,
      isApiEnabled: apiEnabled ?? this.isApiEnabled,
      includeLegacy: includeLegacy ?? this.includeLegacy,
    );
  }

  Map<String, dynamic> toServiceQueryParameters() {
    final map = <String, dynamic>{
      'q': query,
      'platform': platform,
      'tags': tagsPredicate?.toQueryParameters(),
      'uploaderOrPublishers': uploaderOrPublishers,
      'publisherId': publisherId,
      'offset': offset?.toString(),
      'limit': limit?.toString(),
      'order': serializeSearchOrder(order),
      'ad': isAd ? '1' : null,
      'api': isApiEnabled ? null : '0',
      'legacy': includeLegacy ? '1' : null,
    };
    map.removeWhere((k, v) => v == null);
    return map;
  }

  bool get hasQuery => query != null && query.isNotEmpty;

  /// Converts the query to a user-facing link that the search form can use as
  /// the base path of its `action` parameter.
  String toSearchFormPath() {
    String path = '/packages';
    if (platform != null && platform.isNotEmpty) {
      path = '/$platform/packages';
    }
    if (publisherId != null && publisherId.isNotEmpty) {
      path = '/publishers/$publisherId/packages';
    }
    if (uploaderOrPublishers != null && uploaderOrPublishers.isNotEmpty) {
      path = '/my-packages';
    }
    return path;
  }

  /// Converts the query to a user-facing link that (after frontend parsing) will
  /// re-create an identical search query object.
  String toSearchLink({int page}) {
    final Map<String, String> params = {};
    if (query != null && query.isNotEmpty) {
      params['q'] = query;
    }
    if (order != null) {
      final String paramName = 'sort';
      params[paramName] = serializeSearchOrder(order);
    }
    if (!isApiEnabled) {
      params['api'] = '0';
    }
    if (includeLegacy) {
      params['legacy'] = '1';
    }
    if (page != null && page > 1) {
      params['page'] = page.toString();
    }
    final path = toSearchFormPath();
    if (params.isEmpty) {
      return path;
    } else {
      return Uri(path: path, queryParameters: params).toString();
    }
  }
}

/// Filter conditions on tags.
class TagsPredicate {
  final List<String> requiredTags;
  final List<String> negatedTags;

  TagsPredicate({List<String> requiredTags, List<String> negatedTags})
      : requiredTags = requiredTags ?? <String>[],
        negatedTags = negatedTags ?? <String>[];

  bool get isEmpty => requiredTags.isEmpty && negatedTags.isEmpty;

  /// Parses [values] passed via Uri.queryParameters
  factory TagsPredicate.parseQueryValues(List<String> values) {
    final requiredTags = <String>[];
    final negatedTags = <String>[];
    for (String tag in values ?? const <String>[]) {
      bool required = true;
      if (tag.startsWith('-')) {
        tag = tag.substring(1);
        required = false;
      } else if (tag.startsWith('+')) {
        tag = tag.substring(1);
      }
      if (required) {
        requiredTags.add(tag);
      } else {
        negatedTags.add(tag);
      }
    }
    return TagsPredicate(requiredTags: requiredTags, negatedTags: negatedTags);
  }

  /// Evaluate this predicate against the list of supplied [tags].
  /// Returns true if the predicate matches the [tags], false otherwise.
  bool evaluate(List<String> tags) {
    tags ??= const <String>[];
    for (final tag in requiredTags) {
      if (!tags.contains(tag)) return false;
    }
    for (final tag in negatedTags) {
      if (tags.contains(tag)) return false;
    }
    return true;
  }

  /// Returns the list of tag values that can be passed to search service URL.
  List<String> toQueryParameters() {
    return <String>[
      ...requiredTags,
      ...negatedTags.map((s) => '-$s'),
    ];
  }
}

class ParsedQuery {
  final String text;
  final String packagePrefix;

  /// Dependency match for direct or dev dependency.
  final List<String> refDependencies;

  /// Dependency match for all dependencies, including transitive ones.
  final List<String> allDependencies;

  /// Match the publisher of the package.
  final String publisher;

  /// Match uploader emails.
  final List<String> emails;

  /// Enable experimental API search.
  final bool isApiEnabled;

  ParsedQuery._(
    this.text,
    this.packagePrefix,
    this.refDependencies,
    this.allDependencies,
    this.publisher,
    this.emails,
    this.isApiEnabled,
  );

  factory ParsedQuery._parse(String q) {
    String queryText = q ?? '';
    queryText = ' $queryText ';
    String packagePrefix;
    final Match pkgMatch = _packageRegexp.firstMatch(queryText);
    if (pkgMatch != null) {
      packagePrefix = pkgMatch.group(1);
      queryText = queryText.replaceFirst(_packageRegexp, ' ');
    }

    List<String> extractRegExp(RegExp regExp) {
      final List<String> values =
          regExp.allMatches(queryText).map((Match m) => m.group(1)).toList();
      if (values.isNotEmpty) {
        queryText = queryText.replaceAll(regExp, ' ');
      }
      return values;
    }

    final List<String> dependencies = extractRegExp(_refDependencyRegExp);
    final List<String> allDependencies = extractRegExp(_allDependencyRegExp);
    final List<String> emails = extractRegExp(_emailRegexp);
    final allPublishers = extractRegExp(_publisherRegexp);
    final publisher = allPublishers.isEmpty ? null : allPublishers.first;

    final bool isApiEnabled = queryText.contains(' !!api ');
    if (isApiEnabled) {
      queryText = queryText.replaceFirst(' !!api ', ' ');
    }

    queryText = queryText.replaceAll(_whitespacesRegExp, ' ').trim();
    if (queryText.isEmpty) {
      queryText = null;
    }

    return ParsedQuery._(
      queryText,
      packagePrefix,
      dependencies,
      allDependencies,
      publisher,
      emails,
      isApiEnabled,
    );
  }

  bool get hasAnyDependency =>
      refDependencies.isNotEmpty || allDependencies.isNotEmpty;
}

@JsonSerializable()
class PackageSearchResult {
  /// The last update of the search index.
  final String indexUpdated;
  final int totalCount;
  final List<PackageScore> packages;

  PackageSearchResult(
      {this.indexUpdated, this.totalCount, List<PackageScore> packages})
      : this.packages = packages ?? [];

  PackageSearchResult.notReady()
      : indexUpdated = null,
        totalCount = 0,
        packages = [];

  factory PackageSearchResult.fromJson(Map<String, dynamic> json) =>
      _$PackageSearchResultFromJson(json);

  /// Whether the search service has already updated its index after a startup.
  bool get isLegit => indexUpdated != null;

  Map<String, dynamic> toJson() => _$PackageSearchResultToJson(this);
}

@JsonSerializable()
class PackageScore {
  final String package;

  @JsonKey(includeIfNull: false)
  final double score;

  @JsonKey(includeIfNull: false)
  final String url;

  @JsonKey(includeIfNull: false)
  final String version;

  @JsonKey(includeIfNull: false)
  final String description;

  @JsonKey(includeIfNull: false)
  final List<ApiPageRef> apiPages;

  PackageScore({
    this.package,
    this.score,
    this.url,
    this.version,
    this.description,
    this.apiPages,
  });

  factory PackageScore.fromJson(Map<String, dynamic> json) =>
      _$PackageScoreFromJson(json);

  PackageScore change({
    double score,
    String url,
    String version,
    String description,
    List<ApiPageRef> apiPages,
  }) {
    return PackageScore(
      package: package,
      score: score ?? this.score,
      url: url ?? this.url,
      version: version ?? this.version,
      description: description ?? this.description,
      apiPages: apiPages ?? this.apiPages,
    );
  }

  bool get isExternal => url != null && version != null && description != null;

  Map<String, dynamic> toJson() => _$PackageScoreToJson(this);
}

@JsonSerializable()
class ApiPageRef {
  final String title;
  final String path;

  @JsonKey(includeIfNull: false)
  final String url;

  ApiPageRef({this.title, this.path, this.url});

  factory ApiPageRef.fromJson(Map<String, dynamic> json) =>
      _$ApiPageRefFromJson(json);

  ApiPageRef change({String title, String url}) {
    return ApiPageRef(
      title: title ?? this.title,
      path: path,
      url: url ?? this.url,
    );
  }

  Map<String, dynamic> toJson() => _$ApiPageRefToJson(this);
}

/// Extracts the 'page' query parameter from requested URL's [queryParameters].
///
/// Returns a valid positive integer.
int extractPageFromUrlParameters(Map<String, String> queryParameters) {
  final pageAsString = queryParameters['page'];
  final pageAsInt = int.tryParse(pageAsString ?? '1') ?? 1;
  return max(pageAsInt, 1);
}

/// Parses the search query URL queryParameters for the parameters we expose on
/// the frontend. The parameters and the values may be different from the ones
/// we use in the search service backend.
SearchQuery parseFrontendSearchQuery(
  Map<String, String> queryParameters, {
  String platform,
  List<String> uploaderOrPublishers,
  String publisherId,
}) {
  final int page = extractPageFromUrlParameters(queryParameters);
  final int offset = resultsPerPage * (page - 1);
  final String queryText = queryParameters['q'] ?? '';
  final String sortParam = queryParameters['sort'];
  final SearchOrder sortOrder = parseSearchOrder(sortParam);
  final isApiEnabled = queryParameters['api'] != '0';
  return SearchQuery.parse(
    query: queryText,
    platform: platform,
    uploaderOrPublishers: uploaderOrPublishers,
    publisherId: publisherId,
    order: sortOrder,
    offset: offset,
    limit: resultsPerPage,
    apiEnabled: isApiEnabled,
    includeLegacy: queryParameters['legacy'] == '1',
  );
}
