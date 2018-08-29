// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: annotate_overrides

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:gcloud/db.dart';
import 'package:gcloud/storage.dart';
import 'package:gcloud/service_scope.dart' as ss;
import 'package:json_annotation/json_annotation.dart';

import '../dartdoc/pub_dartdoc_data.dart';
import '../frontend/model_properties.dart';
import '../frontend/models.dart';
import '../shared/analyzer_client.dart';
import '../shared/dartdoc_client.dart';
import '../shared/popularity_storage.dart';
import '../shared/search_service.dart';
import '../shared/utils.dart';

import 'text_utils.dart';

part 'backend.g.dart';

final Logger _logger = new Logger('pub.search.backend');
final GZipCodec _gzip = new GZipCodec();

/// Sets the backend service.
void registerSearchBackend(SearchBackend backend) =>
    ss.register(#_searchBackend, backend);

/// The active backend service.
SearchBackend get searchBackend => ss.lookup(#_searchBackend) as SearchBackend;

/// Sets the snapshot storage
void registerSnapshotStorage(SnapshotStorage storage) =>
    ss.register(#_snapshotStorage, storage);

/// The active snapshot storage
SnapshotStorage get snapshotStorage =>
    ss.lookup(#_snapshotStorage) as SnapshotStorage;

/// Datastore-related access methods for the search service
class SearchBackend {
  final DatastoreDB _db;

  SearchBackend(this._db);

  /// Loads the list of packages, their latest stable versions and returns a
  /// matching list of [PackageDocument] objects for search.
  /// When a package, its latest version or its analysis is missing, the method
  /// returns with null at the given index.
  Future<List<PackageDocument>> loadDocuments(List<String> packageNames) async {
    final List<Key> packageKeys = packageNames
        .map((String name) => _db.emptyKey.append(Package, id: name))
        .toList();
    final packages = (await _db.lookup(packageKeys)).cast<Package>();

    // Load only for the existing packages.
    final List<Key> versionKeys = packages
        .where((p) => p != null)
        .map((p) => p.latestVersionKey)
        .toList();
    final versionList = (await _db.lookup(versionKeys)).cast<PackageVersion>();
    final Map<String, PackageVersion> versions = new Map.fromIterable(
        versionList.where((pv) => pv != null),
        key: (pv) => (pv as PackageVersion).package);

    final pubDataFutures = Future.wait(packages.map((p) =>
        dartdocClient.getContentBytes(p.name, 'latest', 'pub-data.json',
            timeout: const Duration(seconds: 10))));

    final List<AnalysisView> analysisViews =
        await analyzerClient.getAnalysisViews(packages.map((p) =>
            p == null ? null : new AnalysisKey(p.name, p.latestVersion)));

    final pubDataContents = await pubDataFutures;

    final List<PackageDocument> results = new List(packages.length);
    for (int i = 0; i < packages.length; i++) {
      final Package p = packages[i];
      if (p == null) continue;
      final PackageVersion pv = versions[p.name];
      if (pv == null) continue;

      final analysisView = analysisViews[i];
      final double popularity = popularityStorage.lookup(pv.package) ?? 0.0;

      final List<int> pubDataContent = pubDataContents[i];
      List<ApiDocPage> apiDocPages;
      if (pubDataContent != null) {
        try {
          apiDocPages = _apiDocPagesFromPubData(pubDataContent);
        } catch (e, st) {
          _logger.severe('Parsing pub-data.json failed.', e, st);
        }
      }

      results[i] = new PackageDocument(
        package: pv.package,
        version: p.latestVersion,
        devVersion: p.latestDevVersion,
        platforms: analysisView.platforms,
        description: compactDescription(pv.pubspec.description),
        created: p.created,
        updated: pv.created,
        readme: compactReadme(pv.readmeContent),
        isDiscontinued: p.isDiscontinued ?? false,
        doNotAdvertise: p.doNotAdvertise ?? false,
        health: analysisView.health,
        popularity: popularity,
        maintenance: analysisView.maintenanceScore,
        dependencies: _buildDependencies(analysisView),
        emails: _buildEmails(p, pv),
        apiDocPages: apiDocPages,
        timestamp: new DateTime.now().toUtc(),
      );
    }
    return results;
  }

  Map<String, String> _buildDependencies(AnalysisView view) {
    final Map<String, String> dependencies = <String, String>{};
    view.allDependencies?.forEach((pd) {
      dependencies[pd.package] = pd.dependencyType;
    });
    return dependencies;
  }

  List<String> _buildEmails(Package p, PackageVersion pv) {
    final Set<String> emails = new Set<String>();
    emails.addAll(p.uploaderEmails.cast<String>());
    for (String value in pv.pubspec.authors) {
      final Author author = new Author.parse(value);
      if (author.email == null) continue;
      emails.add(author.email);
    }
    return emails.toList()..sort();
  }

  List<ApiDocPage> _apiDocPagesFromPubData(List<int> bytes) {
    final decodedMap = json.decode(utf8.decode(bytes)) as Map;
    final pubData = new PubDartdocData.fromJson(decodedMap.cast());

    final nameToKindMap = <String, String>{};
    pubData.apiElements.forEach((e) {
      nameToKindMap[e.name] = e.kind;
    });

    final pathMap = <String, String>{};
    final symbolMap = <String, Set<String>>{};
    final docMap = <String, List<String>>{};

    bool isTopLevel(String kind) => kind == 'library' || kind == 'class';

    void update(String key, String name, String documentation) {
      final set = symbolMap.putIfAbsent(key, () => new Set<String>());
      set.addAll(name.split('.'));

      documentation = documentation?.trim();
      if (documentation != null && documentation.isNotEmpty) {
        final list = docMap.putIfAbsent(key, () => []);
        list.add(compactReadme(documentation));
      }
    }

    pubData.apiElements.forEach((apiElement) {
      if (isTopLevel(apiElement.kind)) {
        pathMap[apiElement.name] = apiElement.href;
        update(apiElement.name, apiElement.name, apiElement.documentation);
      }

      if (!isTopLevel(apiElement.kind) &&
          apiElement.parent != null &&
          isTopLevel(nameToKindMap[apiElement.parent])) {
        update(apiElement.parent, apiElement.name, apiElement.documentation);
      }
    });

    final results = pathMap.keys.map((key) {
      final path = pathMap[key];
      final symbols = symbolMap[key].toList()..sort();
      return new ApiDocPage(
        relativePath: path,
        symbols: symbols,
        textBlocks: docMap[key],
      );
    }).toList();
    results.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return results;
  }
}

class SnapshotStorage {
  final String _latestPath = 'snapshot-latest.json.gz';
  final Storage storage;
  final Bucket bucket;

  SnapshotStorage(this.storage, this.bucket);

  Future<SearchSnapshot> fetch() async {
    try {
      final Map<String, dynamic> map = await bucket
          .read(_latestPath)
          .transform(_gzip.decoder)
          .transform(utf8.decoder)
          .transform(json.decoder)
          .single;
      return new SearchSnapshot.fromJson(map);
    } catch (e, st) {
      _logger.shout(
          'Unable to load search snapshot: ${bucketUri(bucket, _latestPath)}',
          e,
          st);
    }
    return null;
  }

  Future store(SearchSnapshot snapshot) async {
    final List<int> buffer =
        _gzip.encode(utf8.encode(json.encode(snapshot.toJson())));
    await bucket.writeBytes(_latestPath, buffer);
  }
}

@JsonSerializable()
class SearchSnapshot {
  @JsonKey(nullable: false)
  DateTime updated;

  @JsonKey(nullable: false)
  Map<String, PackageDocument> documents;

  SearchSnapshot._(this.updated, this.documents);

  factory SearchSnapshot() =>
      new SearchSnapshot._(new DateTime.now().toUtc(), {});

  factory SearchSnapshot.fromJson(Map<String, dynamic> json) =>
      _$SearchSnapshotFromJson(json);

  void add(PackageDocument doc) {
    updated = new DateTime.now().toUtc();
    documents[doc.package] = doc;
  }

  void addAll(Iterable<PackageDocument> docs) {
    docs.forEach(add);
  }

  void remove(String packageName) {
    updated = new DateTime.now().toUtc();
    documents.remove(packageName);
  }

  Map<String, dynamic> toJson() => _$SearchSnapshotToJson(this);
}
