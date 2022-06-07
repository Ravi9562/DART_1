// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_pub_shared/data/package_api.dart';
import 'package:pub_dev/audit/backend.dart';
import 'package:pub_dev/audit/models.dart';
import 'package:pub_dev/package/backend.dart';
import 'package:pub_dev/tool/utils/pub_api_client.dart';
import 'package:test/test.dart';

import '../shared/handlers_test_utils.dart';
import '../shared/test_models.dart';
import '../shared/test_services.dart';

void main() {
  group('Update value through API', () {
    setupTestsWithCallerAuthorizationIssues(
      (client) =>
          client.setAutomatedPublishing('oxygen', AutomatedPublishing()),
    );

    testWithProfile('no package', fn: () async {
      await withHttpPubApiClient(
        bearerToken: userAtPubDevAuthToken,
        fn: (client) async {
          await expectApiException(
            client.setAutomatedPublishing(
                'no_such_package', AutomatedPublishing()),
            status: 404,
            code: 'NotFound',
          );
        },
      );
    });

    testWithProfile('not admin', fn: () async {
      await withHttpPubApiClient(
        bearerToken: userAtPubDevAuthToken,
        fn: (client) async {
          await expectApiException(
            client.setAutomatedPublishing('oxygen', AutomatedPublishing()),
            status: 403,
            code: 'InsufficientPermissions',
            message:
                'Insufficient permissions to perform administrative actions on package `oxygen`.',
          );
        },
      );
    });

    testWithProfile('successful update', fn: () async {
      await withHttpPubApiClient(
        bearerToken: adminAtPubDevAuthToken,
        fn: (client) async {
          final rs = await client.setAutomatedPublishing(
              'oxygen',
              AutomatedPublishing(
                github: GithubPublishing(
                  isEnabled: true,
                  repository: 'dart-lang/pub-dev',
                ),
              ));
          expect(rs.toJson(), {
            'github': {
              'isEnabled': true,
              'repository': 'dart-lang/pub-dev',
            },
          });
          final p = await packageBackend.lookupPackage('oxygen');
          expect(p!.automatedPublishing.toJson(), rs.toJson());
          final audits = await auditBackend.listRecordsForPackage('oxygen');
          // check audit log record exists
          final record = audits.records.firstWhere((e) =>
              e.kind == AuditLogRecordKind.packagePublicationAutomationUpdated);
          expect(record.created, isNotNull);
          expect(record.summary,
              '`admin@pub.dev` updated the publication automation config of package `oxygen`.');
        },
      );
    });

    testWithProfile('bad project path', fn: () async {
      await withHttpPubApiClient(
        bearerToken: adminAtPubDevAuthToken,
        fn: (client) async {
          final badPaths = [
            '/',
            'a/',
            '/b',
            '//',
            'a/b/c',
            'a /b',
            '(/b',
          ];
          for (final repository in badPaths) {
            final rs = client.setAutomatedPublishing(
                'oxygen',
                AutomatedPublishing(
                  github: GithubPublishing(
                    isEnabled: false,
                    repository: repository,
                  ),
                ));
            await expectApiException(
              rs,
              status: 400,
              code: 'InvalidInput',
            );
          }
        },
      );
    });
  });
}
