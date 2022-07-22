// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:clock/clock.dart';
import 'package:gcloud/db.dart';
import 'package:gcloud/service_scope.dart';
import 'package:logging/logging.dart';
import 'package:pub_dev/account/auth_provider.dart';
import 'package:pub_dev/account/models.dart';
import 'package:pub_dev/fake/backend/fake_auth_provider.dart';
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
import 'package:pub_dev/shared/env_config.dart';
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

export 'package:pub_dev/tool/utils/pub_api_client.dart';

/// Registers test with [name] and runs it in pkg/fake_gcloud's scope, populated
/// with [testProfile] data.
void testWithProfile(
  String name, {
  TestProfile? testProfile,
  ImportSource? importSource,
  required Future<void> Function() fn,
  Timeout? timeout,
  bool processJobsWithFakeRunners = false,
  Pattern? integrityProblem,
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
        if (problems.isNotEmpty &&
            (integrityProblem == null ||
                integrityProblem.matchAsPrefix(problems.first) == null)) {
          throw Exception(
              '${problems.length} integrity problems detected. First: ${problems.first}');
        } else if (problems.isEmpty && integrityProblem != null) {
          throw Exception('Integrity problem expected but not present.');
        }
      },
    );
  }, timeout: timeout);
}

bool _loggingDone = false;

class _LoggerNamePattern {
  final bool negated;
  final RegExp pattern;
  _LoggerNamePattern(this.negated, this.pattern);
}

/// Setup logging if environment variable `DEBUG` is defined.
///
/// Logs are filtered based on `DEBUG='<filter>'`. This is simple filter
/// operating on log names.
///
/// **Examples**:
///  * `DEBUG='*'`, will show output from all loggers.
///  * `DEBUG='pub.*'`, will show output from loggers with name prefixed 'pub.'.
///  * `DEBUG='* -neat_cache'`, will show output from all loggers, except 'neat_cache'.
///
/// Multiple filters can be applied, the last matching filter will be applied.
void setupLogging() {
  if (_loggingDone) {
    return;
  }
  _loggingDone = true;
  final debugEnv = (envConfig.debug ?? '').trim();
  if (debugEnv.isEmpty) {
    return;
  }

  final patterns = debugEnv.split(' ').map((s) {
    var pattern = s.trim();
    final negated = pattern.startsWith('-');
    if (negated) {
      pattern = pattern.substring(1);
    }

    return _LoggerNamePattern(
      negated,
      RegExp('^' +
          pattern.splitMapJoin(
            '*',
            onMatch: (m) => '.*',
            onNonMatch: RegExp.escape,
          ) +
          '\$'),
    );
  }).toList();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    final time = clock.now(); // rec.time

    var matched = false;
    for (final p in patterns) {
      if (p.pattern.hasMatch(rec.loggerName)) {
        matched = !p.negated;
      }
    }
    if (!matched) {
      return;
    }

    for (final line in rec.message.split('\n')) {
      print('$time [${rec.loggerName}] ${rec.level.name}: $line');
    }
    if (rec.error != null) {
      print('ERROR: ${rec.error}, ${rec.stackTrace}');
    }
  });
}

void setupTestsWithCallerAuthorizationIssues(
  Future Function(PubApiClient client) fn, {
  AuthSource? authSource,
}) {
  testWithProfile('No active user', fn: () async {
    final rs = fn(createPubApiClient());
    await expectApiException(rs, status: 401, code: 'MissingAuthentication');
  });

  testWithProfile('Active user is not authorized', fn: () async {
    final token =
        createFakeAuthTokenForEmail('unauthorized@pub.dev', source: authSource);
    final rs = fn(createPubApiClient(authToken: token));
    await expectApiException(rs, status: 403, code: 'InsufficientPermissions');
  });

  testWithProfile('Active user is blocked', fn: () async {
    final users = await dbService.query<User>().run().toList();
    final user = users.firstWhere((u) => u.email == 'admin@pub.dev');
    await dbService.commit(inserts: [user..isBlocked = true]);
    final token =
        createFakeAuthTokenForEmail('admin@pub.dev', source: authSource);
    final rs = fn(createPubApiClient(authToken: token));
    await expectApiException(rs,
        status: 403,
        code: 'InsufficientPermissions',
        message: 'User is blocked.');
  });
}
