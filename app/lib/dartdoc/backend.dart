// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:gcloud/service_scope.dart' as ss;
import 'package:gcloud/storage.dart';
import 'package:indexed_blob/indexed_blob.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:retry/retry.dart';

import '../package/models.dart' show Package, PackageVersion;
import '../shared/datastore.dart';
import '../shared/redis_cache.dart' show cache;
import '../shared/storage.dart';
import '../shared/versions.dart' as shared_versions;

import 'models.dart';
import 'storage_path.dart' as storage_path;

/// Files that are served from inside the blob.
const archiveFilePath = 'package.tar.gz';
const blobFilePath = 'blob-data.gz';
const blobIndexV1FilePath = 'index-v1.json';
const buildLogFilePath = 'log.txt';
const _uploadedFilePaths = [
  archiveFilePath,
  blobFilePath,
  blobIndexV1FilePath,
  buildLogFilePath,
];

final Logger _logger = Logger('pub.dartdoc.backend');

final int _concurrentUploads = 8;
final int _concurrentDeletes = 4;

/// Sets the dartdoc backend.
void registerDartdocBackend(DartdocBackend backend) =>
    ss.register(#_dartdocBackend, backend);

/// The active dartdoc backend.
DartdocBackend get dartdocBackend =>
    ss.lookup(#_dartdocBackend) as DartdocBackend;

class DartdocBackend {
  final DatastoreDB _db;
  final Bucket _storage;
  final VersionedJsonStorage _sdkStorage;

  DartdocBackend(this._db, this._storage)
      : _sdkStorage =
            VersionedJsonStorage(_storage, storage_path.dartSdkDartdocPrefix());

  /// Deletes old data files in SDK storage (for old runtimes that are more than
  /// half a year old).
  Future<void> deleteOldData() async {
    final counts = await _sdkStorage.deleteOldData();
    _logger.info('Deleted old dartdoc SDK data: $counts.');
  }

  Future<List<String>> getLatestVersions(String package,
      {int limit = 10}) async {
    final query = _db.query<PackageVersion>(
        ancestorKey: _db.emptyKey.append(Package, id: package));
    final versions = await query.run().cast<PackageVersion>().toList();
    versions.sort((a, b) {
      final isAPreRelease = a.semanticVersion.isPreRelease;
      final isBPreRelease = b.semanticVersion.isPreRelease;
      if (isAPreRelease != isBPreRelease) {
        return isAPreRelease ? 1 : -1;
      }
      return -a.created!.compareTo(b.created!);
    });
    return versions.map((pv) => pv.version!).take(limit).toList();
  }

  /// Updates the [oldEntry] entry with the current isLatest value.
  Future<void> updateOldIsLatest(
    DartdocEntry oldEntry, {
    required bool isLatest,
  }) async {
    await withRetryTransaction(_db, (tx) async {
      final oldRun = await tx.lookupOrNull<DartdocRun>(
          _db.emptyKey.append(DartdocRun, id: oldEntry.uuid));
      if (oldRun == null) {
        return;
      }
      final oldStoredEntry = oldRun.entry;
      if (oldStoredEntry!.isLatest == isLatest) {
        return;
      }
      oldRun.wasLatestStable = isLatest;
      tx.insert(oldRun);
    });
  }

  /// Uploads a directory to the storage bucket.
  Future<void> uploadDir(DartdocEntry entry, String dirPath) async {
    final oldRunsQuery = _db.query<DartdocRun>()
      ..filter(
          'packageVersionRuntime =',
          [entry.packageName, entry.packageVersion, entry.runtimeVersion]
              .join('/'));
    final oldRuns = await oldRunsQuery.run().toList();

    final run = DartdocRun.fromEntry(entry, status: DartdocRunStatus.uploading);
    // store the current run's upload status
    await withRetryTransaction(_db, (tx) async {
      tx.insert(run);
    });

    // upload all files
    final dir = Directory(dirPath);
    final Stream<File> fileStream = dir
        .list(recursive: true)
        .where((fse) => fse is File)
        .map((fse) => fse as File);

    int count = 0;
    Future<void> upload(File file) async {
      final relativePath = p.relative(file.path, from: dir.path);
      final objectName = entry.objectName(relativePath);
      final isShared = storage_path.isSharedAsset(relativePath);
      if (isShared) {
        final info = await getFileInfo(entry, relativePath);
        if (info != null) return;
      }
      await uploadWithRetry(
          _storage, objectName, file.lengthSync(), () => file.openRead());
      count++;
    }

    final sw = Stopwatch()..start();
    final uploadPool = Pool(_concurrentUploads);
    final List<Future> uploadFutures = [];
    await for (File file in fileStream) {
      final pooledUpload = uploadPool.withResource(() => upload(file));
      uploadFutures.add(pooledUpload);
    }
    await Future.wait(uploadFutures);
    await uploadPool.close();
    sw.stop();
    _logger.info('${entry.packageName} ${entry.packageVersion}: '
        '$count files uploaded in ${sw.elapsed}.');

    // upload was completed
    await withRetryTransaction(_db, (tx) async {
      final r = await tx.lookupValue<DartdocRun>(run.key);
      if (r.status == DartdocRunStatus.uploading) {
        r.status = DartdocRunStatus.ready;
        tx.insert(r);
      }
    });

    await Future.wait([
      cache.dartdocEntry(entry.packageName, entry.packageVersion).purge(),
      cache.dartdocEntry(entry.packageName, 'latest').purge(),
    ]);

    // Mark old content as expired.
    if (run.hasValidContent! && oldRuns.isNotEmpty) {
      await withRetryTransaction(_db, (tx) async {
        for (final old in oldRuns) {
          if (old.isExpired!) continue;
          final r = await tx.lookupOrNull<DartdocRun>(old.key);
          if (r == null || r.isExpired!) continue;
          r.isExpired = true;
          tx.insert(r);
        }
      });
    }
  }

  /// Returns the file's header from the storage bucket
  Future<FileInfo?> getFileInfo(DartdocEntry entry, String relativePath) async {
    final objectName = entry.objectName(relativePath);
    return await cache.dartdocFileInfo(objectName).get(
          () async => retry<FileInfo?>(
            () async {
              try {
                if (_uploadedFilePaths.contains(relativePath)) {
                  final info = await _storage.info(objectName);
                  return FileInfo(lastModified: info.updated, etag: info.etag);
                }
                final index = await _getBlobIndex(entry);
                final range = index?.lookup(relativePath);
                if (range == null) {
                  return null;
                }
                return FileInfo(
                  lastModified: entry.timestamp!,
                  etag: '${entry.uuid}-${range.start}-${range.end}',
                  blobId: entry.uuid,
                  blobOffset: range.start,
                  blobLength: range.length,
                );
              } catch (e) {
                // TODO: Handle exceptions / errors
                _logger.info('Requested path $objectName does not exists.');
                return null;
              }
            },
            maxAttempts: 2,
          ),
        );
  }

  Future<BlobIndex?> _getBlobIndex(DartdocEntry entry) async {
    if (!entry.hasBlob) return null;
    final objectName = entry.objectName(blobIndexV1FilePath);
    final indexContent =
        await cache.dartdocBlobIndexV1(objectName).get(() async {
      return await _storage.readAsBytes(objectName);
    });
    if (indexContent == null) return null;
    return BlobIndex.fromBytes(indexContent);
  }

  /// Returns a file's content from the storage bucket.
  Stream<List<int>> readContent(DartdocEntry entry, String relativePath) {
    final objectName = entry.objectName(relativePath);
    // TODO: add caching with memcache
    _logger.info('Retrieving $objectName from bucket.');
    return _storage.read(objectName);
  }

  /// Reads content from blob.
  Stream<List<int>> readFromBlob(DartdocEntry entry, FileInfo info) {
    return _storage.read(
      entry.objectName(blobFilePath),
      offset: info.blobOffset!,
      length: info.blobLength!,
    );
  }

  /// Removes all files related to a package.
  Future<void> removeAll(String package,
      {String? version, int? concurrency}) async {
    final prefix = version == null ? '$package/' : '$package/$version/';
    await _deleteAllWithPrefix(prefix, concurrency: concurrency);
  }

  /// Scan the Datastore for [DartdocRun]s and remove the ones that
  /// predate [shared_versions.gcBeforeRuntimeVersion]. This will delete
  /// both the Datastore entity and the Storage Bucket's content.
  Future<void> deleteOldRuns() async {
    final query = _db.query<DartdocRun>()
      ..filter('runtimeVersion <', shared_versions.gcBeforeRuntimeVersion);
    await for (final r in query.run()) {
      await _deleteAll(r.entry!);
    }
  }

  /// Scan the Datastore for [DartdocRun]s and remove the ones that
  /// are marked as expired. This will delete both the Datastore entity and
  /// the Storage Bucket's content.
  Future<void> deleteExpiredRuns() async {
    final query = _db.query<DartdocRun>()..filter('isExpired =', true);
    await for (final r in query.run()) {
      await _deleteAll(r.entry!);
    }
  }

  Future<void> _deleteAll(DartdocEntry entry) async {
    await withRetryTransaction(_db, (tx) async {
      final r = await tx.lookupOrNull<DartdocRun>(
          _db.emptyKey.append(DartdocRun, id: entry.uuid));
      if (r != null) {
        r.status = DartdocRunStatus.deleting;
        tx.insert(r);
      }
    });

    await _deleteAllWithPrefix(entry.contentPrefix);
    await withRetryTransaction(_db, (tx) async {
      final r = await tx.lookupOrNull<DartdocRun>(
          _db.emptyKey.append(DartdocRun, id: entry.uuid));
      if (r != null) {
        tx.delete(r.key);
      }
    });
  }

  Future<void> _deleteAllWithPrefix(String prefix, {int? concurrency}) async {
    final Stopwatch sw = Stopwatch()..start();
    final count = await deleteBucketFolderRecursively(_storage, prefix,
        concurrency: concurrency ?? _concurrentDeletes);
    sw.stop();
    _logger.info('$prefix: $count files deleted in ${sw.elapsed}.');
  }
}
