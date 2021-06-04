// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:gcloud/db.dart';
import 'package:gcloud/service_scope.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'package:pub_dev/account/models.dart';
import 'package:pub_dev/fake/backend/fake_dartdoc_runner.dart';
import 'package:pub_dev/fake/backend/fake_email_sender.dart';
import 'package:pub_dev/fake/backend/fake_pana_runner.dart';
import 'package:pub_dev/fake/backend/fake_popularity.dart';
import 'package:pub_dev/frontend/handlers/pubapi.client.dart';
import 'package:pub_dev/package/name_tracker.dart';
import 'package:pub_dev/scorecard/backend.dart';
import 'package:pub_dev/search/backend.dart';
import 'package:pub_dev/search/handlers.dart';
import 'package:pub_dev/search/updater.dart';
import 'package:pub_dev/shared/integrity.dart';
import 'package:pub_dev/shared/popularity_storage.dart';
import 'package:pub_dev/search/search_client.dart';
import 'package:pub_dev/service/services.dart';
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
  TestProfile testProfile,
  ImportSource importSource,
  @required Future<void> Function() fn,
  Timeout timeout,
  bool processJobsWithFakeRunners = false,
}) {
  testWithServices(
    name,
    () async {
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
    },
    omitData: true,
    timeout: timeout,
  );
}

/// Setup scoped services for tests.
///
/// If [omitData] is not set to `true`, a default set of user and package data
/// will be populated and indexed in search.
void testWithServices(
  String name,
  Future<void> Function() fn, {
  bool omitData = false,
  Timeout timeout,
}) {
  scopedTest(name, () async {
    _setupLogging();
    await withFakeServices(
      fn: () async {
        if (!omitData) {
          await _populateDefaultData();
        }
        await dartSdkIndex.markReady();
        await indexUpdater.updateAllPackages();

        registerSearchClient(SearchClient(
            httpClientToShelfHandler(handler: searchServiceHandler)));

        registerScopeExitCallback(searchClient.close);

        await fork(() async {
          await fn();
          // post-test integrity check
          final problems = await IntegrityChecker(dbService).check();
          if (problems.isNotEmpty) {
            throw Exception(
                '${problems.length} integrity problems detected. First: ${problems.first}');
          }
        });
      },
    );
  }, timeout: timeout);
}

Future<void> _populateDefaultData() async {
  await dbService.commit(inserts: [
    foobarPackage,
    foobarStablePV,
    foobarDevPV,
    foobarStablePV,
    foobarDevPV,
    foobarStablePvInfo,
    foobarDevPvInfo,
    ...foobarAssets.values,
    testUserA,
    hansUser,
    joeUser,
    hydrogen.package,
    ...hydrogen.versions,
    ...hydrogen.infos,
    ...hydrogen.assets,
    helium.package,
    ...helium.versions,
    ...helium.infos,
    ...helium.assets,
    exampleComPublisher,
    exampleComHansAdmin,
  ]);

  popularityStorage.updateValues({
    hydrogen.package.name: 0.8,
    helium.package.name: 1.0,
  });

  await scoreCardBackend.updateReportAndCard(
      helium.package.name,
      helium.package.latestVersion,
      generatePanaReport(derivedTags: ['sdk:flutter']));
}

/// Creates local, non-HTTP-based API client with [authToken].
PubApiClient createPubApiClient({String authToken}) =>
    createLocalPubApiClient(authToken: authToken);

bool _loggingDone = false;

/// Setup logging if environment variable `DEBUG` is defined.
void _setupLogging() {
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
