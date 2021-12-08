// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:gcloud/db.dart';
import 'package:gcloud/service_scope.dart';
import 'package:logging/logging.dart';
import 'package:pub_dev/account/models.dart';
import 'package:pub_dev/fake/backend/fake_dartdoc_runner.dart';
import 'package:pub_dev/fake/backend/fake_email_sender.dart';
import 'package:pub_dev/fake/backend/fake_pana_runner.dart';
import 'package:pub_dev/fake/backend/fake_popularity.dart';
import 'package:pub_dev/frontend/handlers/pubapi.client.dart';
import 'package:pub_dev/package/name_tracker.dart';
import 'package:pub_dev/search/handlers.dart';
import 'package:pub_dev/search/search_client.dart';
import 'package:pub_dev/search/updater.dart';
import 'package:pub_dev/service/services.dart';
import 'package:pub_dev/shared/integrity.dart';
import 'package:pub_dev/tool/test_profile/import_source.dart';
import 'package:pub_dev/tool/test_profile/importer.dart';
import 'package:pub_dev/tool/test_profile/models.dart';
import 'package:pub_dev/tool/utils/http_client_to_shelf_handler.dart';
import 'package:pub_dev/tool/utils/pub_api_client.dart';
import 'package:test/test.dart';

import '../shared/utils.dart';
import 'handlers_test_utils.dart';
import 'test_models.dart';

/// Registers test with [name] and runs it in pkg/fake_gcloud's scope, populated
/// with [testProfile] data.
void testWithProfile(
  String name, {
  TestProfile? testProfile,
  ImportSource? importSource,
  required Future<void> Function() fn,
  Timeout? timeout,
  bool processJobsWithFakeRunners = false,
}) {
  scopedTest(name, () async {
    setupLogging();
    await withFakeServices(
      fn: () async {
        registerSearchClient(SearchClient(
            httpClientToShelfHandler(handler: searchServiceHandler)));
        registerScopeExitCallback(searchClient.close);

        await importProfile(
          profile: testProfile ?? defaultTestProfile,
          source: importSource ?? ImportSource.autoGenerated(),
        );
        await nameTracker.scanDatastore();
        await generateFakePopularityValues();
        if (processJobsWithFakeRunners) {
          await processJobsWithFakePanaRunner();
          await processJobsWithFakeDartdocRunner();
        }
        await indexUpdater.updateAllPackages();
        fakeEmailSender.sentMessages.clear();

        await fork(() async {
          await fn();
        });
        // post-test integrity check
        final problems =
            await IntegrityChecker(dbService).findProblems().toList();
        if (problems.isNotEmpty) {
          throw Exception(
              '${problems.length} integrity problems detected. First: ${problems.first}');
        }
      },
    );
  }, timeout: timeout);
}

/// Creates local, non-HTTP-based API client with [authToken].
PubApiClient createPubApiClient({String? authToken}) =>
    createLocalPubApiClient(authToken: authToken);

bool _loggingDone = false;

/// Setup logging if environment variable `DEBUG` is defined.
void setupLogging() {
  if (_loggingDone) {
    return;
  }
  _loggingDone = true;
  if ((Platform.environment['DEBUG'] ?? '') == '') {
    return;
  }
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
    if (rec.error != null) {
      print('ERROR: ${rec.error}, ${rec.stackTrace}');
    }
  });
}

void setupTestsWithCallerAuthorizationIssues(
  Future Function(PubApiClient client) fn,
) {
  testWithProfile('No active user', fn: () async {
    final client = createPubApiClient();
    final rs = fn(client);
    await expectApiException(rs, status: 401, code: 'MissingAuthentication');
  });

  testWithProfile('Active user is not authorized', fn: () async {
    final client = createPubApiClient(authToken: unauthorizedAtPubDevAuthToken);
    final rs = fn(client);
    await expectApiException(rs, status: 403, code: 'InsufficientPermissions');
  });

  testWithProfile('Active user is blocked', fn: () async {
    final users = await dbService.query<User>().run().toList();
    final user = users.firstWhere((u) => u.email == 'admin@pub.dev');
    await dbService.commit(inserts: [user..isBlocked = true]);
    final client = createPubApiClient(authToken: adminAtPubDevAuthToken);
    final rs = fn(client);
    await expectApiException(rs,
        status: 403,
        code: 'InsufficientPermissions',
        message: 'User is blocked.');
  });
}
