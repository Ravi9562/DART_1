// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:math';

import 'package:gcloud/db.dart' as db;
import 'package:gcloud/service_scope.dart';
import 'package:gcloud/storage.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:pub_dartlang_org/shared/analyzer_client.dart';
import 'package:pub_dartlang_org/shared/configuration.dart';
import 'package:pub_dartlang_org/shared/dartdoc_client.dart';
import 'package:pub_dartlang_org/shared/deps_graph.dart';
import 'package:pub_dartlang_org/shared/handler_helpers.dart';
import 'package:pub_dartlang_org/shared/popularity_storage.dart';
import 'package:pub_dartlang_org/shared/service_utils.dart';
import 'package:pub_dartlang_org/shared/storage.dart';
import 'package:pub_dartlang_org/shared/services.dart';

import 'package:pub_dartlang_org/frontend/backend.dart';
import 'package:pub_dartlang_org/frontend/cronjobs.dart' show CronJobs;
import 'package:pub_dartlang_org/frontend/handlers.dart';
import 'package:pub_dartlang_org/frontend/name_tracker.dart';
import 'package:pub_dartlang_org/frontend/service_utils.dart';
import 'package:pub_dartlang_org/frontend/static_files.dart';
import 'package:pub_dartlang_org/frontend/upload_signer_service.dart';

final Logger _logger = Logger('pub');
final _random = Random.secure();

Future main() async {
  await startIsolates(
    logger: _logger,
    frontendEntryPoint: _main,
    workerEntryPoint: _worker,
  );
}

Future _main(FrontendEntryMessage message) async {
  setupServiceIsolate();
  message.protocolSendPort
      .send(FrontendProtocolMessage(statsConsumerPort: null));

  await updateLocalBuiltFiles();
  await withServices(() async {
    final shelf.Handler apiHandler = await setupServices(activeConfiguration);

    // Add randomization to reduce race conditions.
    Timer.periodic(Duration(hours: 8, minutes: _random.nextInt(240)), (_) {
      backend.deleteObsoleteInvites();
    });

    final cron = CronJobs(await getOrCreateBucket(
      storageService,
      activeConfiguration.backupSnapshotBucketName,
    ));
    final appHandler = createAppHandler(apiHandler);
    await runHandler(_logger, appHandler,
        sanitize: true, cronHandler: cron.handler);
  });
}

Future<shelf.Handler> setupServices(Configuration configuration) async {
  await popularityStorage.init();
  nameTracker.startTracking();

  UploadSignerService uploadSigner;
  if (envConfig.hasCredentials) {
    final credentials = configuration.credentials;
    uploadSigner = ServiceAccountBasedUploadSigner(credentials);
  } else {
    final authClient = await auth.clientViaMetadataServer();
    registerScopeExitCallback(() async => authClient.close());
    final email = await obtainServiceAccountEmail();
    uploadSigner =
        IamBasedUploadSigner(configuration.projectId, email, authClient);
  }
  registerUploadSigner(uploadSigner);

  return backend.pubServer.requestHandler;
}

Future _worker(WorkerEntryMessage message) async {
  setupServiceIsolate();
  message.protocolSendPort.send(WorkerProtocolMessage());

  await withServices(() async {
    // Updates job entries for analyzer and dartdoc.
    Future triggerDependentAnalysis(
        String package, String version, Set<String> affected) async {
      await analyzerClient.triggerAnalysis(package, version, affected);
      await dartdocClient.triggerDartdoc(package, version, affected);
    }

    final pdb = await PackageDependencyBuilder.loadInitialGraphFromDb(
        db.dbService, triggerDependentAnalysis);
    await pdb.monitorInBackground(); // never returns
  });
}
