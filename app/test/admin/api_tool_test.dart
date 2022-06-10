// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub_dev/account/backend.dart';
import 'package:pub_dev/package/backend.dart';
import 'package:pub_dev/tool/utils/pub_api_client.dart';
import 'package:test/test.dart';

import '../shared/test_models.dart';
import '../shared/test_services.dart';

void main() {
  group('Admin API: tool', () {
    group('bad tool', () {
      setupTestsWithCallerAuthorizationIssues(
        (client) => client.adminExecuteTool('no-such-tool', ''),
        authSource: AuthSource.admin,
      );

      testWithProfile('auth with bad tool', fn: () async {
        await withHttpPubApiClient(
          bearerToken: siteAdminToken,
          fn: (client) async {
            final rs = await client.adminExecuteTool('no-such-tool', '');
            final bodyText = utf8.decode(rs);
            expect(bodyText, contains('Available admin tools:'));
          },
        );
      });
    });

    group('user merger', () {
      setupTestsWithCallerAuthorizationIssues(
        (client) => client.adminExecuteTool('user-merger', ''),
        authSource: AuthSource.admin,
      );

      testWithProfile('help', fn: () async {
        await withHttpPubApiClient(
          bearerToken: siteAdminToken,
          fn: (client) async {
            final rs = await client.adminExecuteTool('user-merger', '--help');
            final bodyText = utf8.decode(rs);
            expect(bodyText, contains('Usage:'));
          },
        );
      });

      testWithProfile('merge all, but no problems detected', fn: () async {
        await withHttpPubApiClient(
          bearerToken: siteAdminToken,
          fn: (client) async {
            final rs = await client.adminExecuteTool('user-merger', '');
            final bodyText = utf8.decode(rs);
            expect(bodyText, 'Fixed 0 `User` entities.');
          },
        );
      });

      testWithProfile('merge two user ids', fn: () async {
        final admin =
            await accountBackend.lookupOrCreateUserByEmail('admin@pub.dev');
        final user =
            await accountBackend.lookupOrCreateUserByEmail('user@pub.dev');
        await withHttpPubApiClient(
          bearerToken: siteAdminToken,
          fn: (client) async {
            final rs = await client.adminExecuteTool(
                'user-merger',
                Uri(pathSegments: [
                  '--from-user-id',
                  admin.userId,
                  '--to-user-id',
                  user.userId,
                ]).toString());
            final bodyText = utf8.decode(rs);
            expect(bodyText, 'Merged `${admin.userId}` into `${user.userId}`.');

            final p = await packageBackend.lookupPackage('oxygen');
            expect(p!.uploaders, [user.userId]);
          },
        );
      });
    });
  });
}
