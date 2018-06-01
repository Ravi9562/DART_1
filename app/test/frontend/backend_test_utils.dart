// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_dartlang_org.backend_test_utils;

import 'dart:async';
import 'dart:io';

import 'package:gcloud/db.dart' as gdb;
import 'package:gcloud/storage.dart';
import 'package:pub_dartlang_org/history/models.dart';
import 'package:pub_server/repository.dart' show AsyncUploadInfo;

import 'package:pub_dartlang_org/frontend/backend.dart';
import 'package:pub_dartlang_org/frontend/upload_signer_service.dart';
import 'package:pub_dartlang_org/history/backend.dart';

import 'utils.dart';

class DatastoreDBMock extends gdb.DatastoreDB {
  final Function commitFun;
  final Function lookupFun;
  final Function queryFun;
  final TransactionMock transactionMock;
  final QueryMock queryMock;

  DatastoreDBMock(
      {this.commitFun,
      this.lookupFun,
      this.queryFun,
      this.queryMock,
      this.transactionMock})
      : super(null);

  @override
  Future commit({List<gdb.Model> inserts, List<gdb.Key> deletes}) async {
    if (commitFun == null) {
      throw new Exception('no commitFun');
    }
    return commitFun(inserts: inserts, deletes: deletes);
  }

  @override
  Future<List<gdb.Model>> lookup(List<gdb.Key> keys) async {
    if (lookupFun == null) {
      throw new Exception('no lookupFun');
    }
    return (await lookupFun(keys)) as List<gdb.Model>;
  }

  @override
  gdb.Query query(Type kind, {gdb.Partition partition, gdb.Key ancestorKey}) {
    if (queryMock == null) {
      throw new Exception('no queryMock');
    }
    queryMock._kind = kind;
    queryMock._partition = partition;
    queryMock._ancestorKey = ancestorKey;
    return queryMock;
  }

  @override
  Future withTransaction(Future handler(gdb.Transaction transaction)) async {
    if (transactionMock == null) {
      throw new Exception('no transactionMock');
    }
    return handler(transactionMock);
  }
}

class TransactionMock implements gdb.Transaction {
  final Function commitFun;
  final Function lookupFun;
  final Function queueMutationFun;
  final Function rollbackFun;
  final QueryMock queryMock;

  @override
  gdb.DatastoreDB get db => throw new Exception('db not supported');

  TransactionMock(
      {this.commitFun,
      this.lookupFun,
      this.queueMutationFun,
      this.rollbackFun,
      this.queryMock});

  @override
  Future commit() async {
    if (commitFun == null) {
      throw new Exception('no commitFun');
    }
    return commitFun();
  }

  @override
  Future<List<gdb.Model>> lookup(List<gdb.Key> keys) async {
    if (lookupFun == null) {
      throw new Exception('no lookupFun');
    }
    return (await lookupFun(keys)) as List<gdb.Model>;
  }

  @override
  gdb.Query query(Type kind, gdb.Key ancestorKey, {gdb.Partition partition}) {
    if (queryMock == null) {
      throw new Exception('no queryMock');
    }
    queryMock._kind = kind;
    queryMock._partition = partition;
    queryMock._ancestorKey = ancestorKey;
    return queryMock;
  }

  @override
  void queueMutations({List<gdb.Model> inserts, List<gdb.Key> deletes}) {
    if (queueMutationFun == null) {
      throw new Exception('no queueMutationFun');
    }
    queueMutationFun(inserts: inserts, deletes: deletes);
  }

  @override
  Future rollback() async {
    if (rollbackFun == null) {
      throw new Exception('no rollbackFun');
    }
    return rollbackFun();
  }
}

class QueryMock implements gdb.Query {
  final QueryMockHandler runFun;

  QueryMock(this.runFun);

  // These will will be set by the query() methods on `Transaction` or
  // `DatastoreDB`.
  Type _kind;
  gdb.Partition _partition;
  gdb.Key _ancestorKey;

  // These will be manipulated during method calls on the query object.
  final List<String> _filters = [];
  final List<String> _filterComparisonObjects = [];
  int _offset;
  int _limit;
  final List<String> _orders = [];

  @override
  void filter(String filterString, Object comparisonObject) {
    _filters.add(filterString);
    _filterComparisonObjects.add(comparisonObject as String);
  }

  @override
  void limit(int limit) {
    _limit = limit;
  }

  @override
  void offset(int offset) {
    _offset = offset;
  }

  @override
  void order(String orderString) => _orders.add(orderString);

  @override
  Stream<gdb.Model> run() {
    return runFun(
        kind: _kind,
        partition: _partition,
        ancestorKey: _ancestorKey,
        filters: _filters,
        filterComparisonObjects: _filterComparisonObjects,
        offset: _offset,
        limit: _limit,
        orders: _orders);
  }
}

typedef Stream<gdb.Model> QueryMockHandler(
    {Type kind,
    gdb.Partition partition,
    gdb.Key ancestorKey,
    List<String> filters,
    List filterComparisonObjects,
    int offset,
    int limit,
    List<String> orders});

class TarballStorageMock implements TarballStorage {
  final Function downloadFun;
  final Function downloadUrlFun;
  final Function readTempObjectFun;
  final Function removeTempObjectFun;
  final Function tmpObjectNameFun;
  final Function uploadFun;
  final Function uploadViaTempObjectFun;
  final BucketMock bucketMock;

  TarballStorageMock(
      {this.downloadFun,
      this.downloadUrlFun,
      this.readTempObjectFun,
      this.removeTempObjectFun,
      this.tmpObjectNameFun,
      this.uploadFun,
      this.uploadViaTempObjectFun,
      this.bucketMock});

  @override
  Bucket get bucket => bucketMock;

  @override
  Storage get storage => throw new Exception('no storage support');

  @override
  TarballStorageNamer get namer => throw new Exception('no namer support');

  @override
  Stream<List<int>> download(String package, String version) {
    if (downloadFun == null) {
      throw new Exception('no downloadFun');
    }
    return downloadFun(package, version) as Stream<List<int>>;
  }

  @override
  Future<Uri> downloadUrl(String package, String version) async {
    if (downloadUrlFun == null) {
      throw new Exception('no downloadUrlFun');
    }
    return (await downloadUrlFun(package, version)) as Uri;
  }

  @override
  Stream<List<int>> readTempObject(String guid) {
    if (readTempObjectFun == null) {
      throw new Exception('no readTempObjectFun');
    }
    return readTempObjectFun(guid) as Stream<List<int>>;
  }

  @override
  Future removeTempObject(String guid) async {
    if (removeTempObjectFun == null) {
      throw new Exception('no removeTempObjectFun');
    }
    return removeTempObjectFun(guid);
  }

  @override
  String tempObjectName(String guid) {
    if (tmpObjectNameFun == null) {
      throw new Exception('no tmpObjectNameFun');
    }
    return tmpObjectNameFun(guid) as String;
  }

  @override
  Future upload(
      String package, String version, Stream<List<int>> tarball) async {
    if (uploadFun == null) {
      throw new Exception('no uploadFun');
    }
    return uploadFun(package, version, tarball);
  }

  @override
  Future uploadViaTempObject(
      String guid, String package, String version) async {
    if (uploadViaTempObjectFun == null) {
      throw new Exception('no uploadViaTempObjectFun');
    }
    return uploadViaTempObjectFun(guid, package, version);
  }

  @override
  Future remove(String package, String version) =>
      throw new UnimplementedError();
}

class UploadSignerServiceMock implements UploadSignerService {
  final Function buildUploadFun;

  UploadSignerServiceMock(this.buildUploadFun);

  @override
  Future<AsyncUploadInfo> buildUpload(String bucket, String object,
      Duration lifetime, String successRedirectUrl,
      {String predefinedAcl: 'project-private',
      int maxUploadSize: UploadSignerService.maxUploadSize}) async {
    return (await buildUploadFun(bucket, object, lifetime, successRedirectUrl,
        predefinedAcl: predefinedAcl,
        maxUploadSize: maxUploadSize)) as AsyncUploadInfo;
  }

  @override
  Future<SigningResult> sign(List<int> bytes) => throw new UnimplementedError();
}

class BucketMock implements Bucket {
  @override
  final String bucketName;

  BucketMock(this.bucketName);

  @override
  String absoluteObjectName(String objectName) {
    throw new UnimplementedError();
  }

  @override
  Future delete(String name) {
    throw new UnimplementedError();
  }

  @override
  Future<ObjectInfo> info(String name) {
    throw new UnimplementedError();
  }

  @override
  Stream<BucketEntry> list({String prefix}) {
    throw new UnimplementedError();
  }

  @override
  Future<Page<BucketEntry>> page({String prefix, int pageSize: 50}) {
    throw new UnimplementedError();
  }

  @override
  Stream<List<int>> read(String objectName, {int offset: 0, int length}) {
    throw new UnimplementedError();
  }

  @override
  Future updateMetadata(String objectName, ObjectMetadata metadata) async {
    throw new UnimplementedError();
  }

  @override
  StreamSink<List<int>> write(String objectName,
      {int length,
      ObjectMetadata metadata,
      Acl acl,
      PredefinedAcl predefinedAcl,
      String contentType}) {
    throw new UnimplementedError();
  }

  @override
  Future<ObjectInfo> writeBytes(String name, List<int> bytes,
      {ObjectMetadata metadata,
      Acl acl,
      PredefinedAcl predefinedAcl,
      String contentType}) async {
    throw new UnimplementedError();
  }
}

Future<T> withTempDirectory<T>(Future<T> func(String temp)) async {
  final Directory dir =
      await Directory.systemTemp.createTemp('pub.dartlang.org-backend-test');
  try {
    return await func(dir.absolute.path);
  } finally {
    await dir.delete(recursive: true);
  }
}

Future withTestPackage(Future func(List<int> tarball),
    {String pubspecContent}) {
  return withTempDirectory((String tmp) async {
    final readme = new File('$tmp/README.md');
    final changelog = new File('$tmp/CHANGELOG.md');
    final pubspec = new File('$tmp/pubspec.yaml');

    await readme.writeAsString(TestPackageReadme);
    await changelog.writeAsString(TestPackageChangelog);
    await pubspec.writeAsString(pubspecContent ?? TestPackagePubspec);

    await new Directory('$tmp/lib').create();
    new File('$tmp/lib/test_library.dart')
        .writeAsString('hello() => print("hello");');

    final files = [
      'README.md',
      'CHANGELOG.md',
      'pubspec.yaml',
      'lib/test_library.dart'
    ];
    final args = ['cz']..addAll(files);
    final Process p =
        await Process.start('tar', args, workingDirectory: '$tmp');
    p.stderr.drain();
    final bytes = await p.stdout.fold<List<int>>([], (b, d) => b..addAll(d));
    final exitCode = await p.exitCode;
    if (exitCode != 0) {
      throw new Exception('Failed to make tarball of test package.');
    }
    return func(bytes);
  });
}

class HistoryBackendMock implements HistoryBackend {
  final storedHistories = <History>[];

  @override
  Stream<History> getAll(
      {String scope, String packageName, String packageVersion, int limit}) {
    throw new UnimplementedError();
  }

  @override
  Future store(History history) async {
    storedHistories.add(history);
  }
}
