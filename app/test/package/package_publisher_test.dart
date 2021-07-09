// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:gcloud/db.dart';
import 'package:test/test.dart';

import 'package:client_data/package_api.dart';
import 'package:pub_dev/account/backend.dart';
import 'package:pub_dev/audit/backend.dart';
import 'package:pub_dev/audit/models.dart';
import 'package:pub_dev/frontend/handlers/pubapi.client.dart';
import 'package:pub_dev/package/backend.dart';
import 'package:pub_dev/publisher/models.dart';
import 'package:pub_dev/shared/exceptions.dart';
import 'package:pub_dev/tool/test_profile/models.dart';

import '../shared/handlers_test_utils.dart';
import '../shared/test_models.dart';
import '../shared/test_services.dart';

import 'backend_test_utils.dart';

void main() {
  group('Get publisher info', () {
    _testNoPackage((client) => client.getPackagePublisher('no_package'));

    testWithProfile('traditional package, not authenticated user',
        fn: () async {
      final client = createPubApiClient();
      final rs = await client.getPackagePublisher('oxygen');
      expect(rs.toJson(), {'publisherId': null});
    });
  });

  group('Set publisher for a traditional package', () {
    _testNoPackage((client) => client.setPackagePublisher(
          'no_package',
          PackagePublisherInfo(publisherId: 'no-domain.net'),
        ));

    _testNoPublisher((client) => client.setPackagePublisher(
          'oxygen',
          PackagePublisherInfo(publisherId: 'no-domain.net'),
        ));

    _testUserNotMemberOfPublisher(
      fn: (client) => client.setPackagePublisher(
        'oxygen',
        PackagePublisherInfo(publisherId: 'example.com'),
      ),
    );

    _testUserNotAdminOfPublisher(
      fn: (client) => client.setPackagePublisher(
        'oxygen',
        PackagePublisherInfo(publisherId: 'example.com'),
      ),
    );

    testWithProfile('User is not an uploader', fn: () async {
      final client = createPubApiClient(authToken: userAtPubDevAuthToken);
      final rs = client.setPackagePublisher(
        'oxygen',
        PackagePublisherInfo(publisherId: 'example.com'),
      );
      await expectApiException(rs,
          status: 403, code: 'InsufficientPermissions');
    });

    testWithProfile('successful', fn: () async {
      final client = createPubApiClient(authToken: adminAtPubDevAuthToken);
      final rs = await client.setPackagePublisher(
        'oxygen',
        PackagePublisherInfo(publisherId: 'example.com'),
      );
      expect(_json(rs.toJson()), {'publisherId': 'example.com'});

      final p = (await packageBackend.lookupPackage('oxygen'))!;
      expect(p.publisherId, 'example.com');
      expect(p.uploaders, []);

      final info = await client.getPackagePublisher('oxygen');
      expect(_json(info.toJson()), _json(rs.toJson()));

      final auditLogs =
          await auditBackend.listRecordsForPublisher('example.com');
      expect(auditLogs.first.kind, AuditLogRecordKind.packageTransferred);
      expect(auditLogs.first.summary,
          'Package `oxygen` was transferred to publisher `example.com` by `admin@pub.dev`.');
    });
  });

  group('Upload with a publisher', () {
    testWithProfile('not an admin', fn: () async {
      final client = createPubApiClient(authToken: adminAtPubDevAuthToken);
      await client.setPackagePublisher(
        'oxygen',
        PackagePublisherInfo(publisherId: 'example.com'),
      );
      await accountBackend.withBearerToken(userAtPubDevAuthToken, () async {
        final tarball = await packageArchiveBytes(
            pubspecContent: generatePubspecYaml('oxygen', '3.0.0'));
        final rs = packageBackend.upload(Stream.fromIterable([tarball]));
        await expectLater(
            rs,
            throwsA(isA<AuthorizationException>()
                .having((a) => a.code, 'code', 'InsufficientPermissions')));
      });
    });

    testWithProfile('successful', fn: () async {
      final client = createPubApiClient(authToken: adminAtPubDevAuthToken);
      await client.setPackagePublisher(
        'oxygen',
        PackagePublisherInfo(publisherId: 'example.com'),
      );
      await accountBackend.withBearerToken(adminAtPubDevAuthToken, () async {
        final tarball = await packageArchiveBytes(
            pubspecContent: generatePubspecYaml('oxygen', '3.0.0'));
        final pv = await packageBackend.upload(Stream.fromIterable([tarball]));
        expect(pv.version.toString(), '3.0.0');
      });
    });
  });

  group('Move between publishers', () {
    TestProfile _profile() => TestProfile(
          packages: [
            TestPackage(name: 'one', publisher: 'verified.com'),
            TestPackage(name: 'two', publisher: 'example.com'),
          ],
          defaultUser: 'admin@pub.dev',
        );

    _testNoPackage((client) async {
      return client.setPackagePublisher(
        'no_package',
        PackagePublisherInfo(publisherId: 'no-domain.net'),
      );
    });

    _testNoPublisher((client) async {
      return client.setPackagePublisher(
        'one',
        PackagePublisherInfo(publisherId: 'no-domain.net'),
      );
    });

    _testNoActiveUser((client) async {
      return client.setPackagePublisher(
        'one',
        PackagePublisherInfo(publisherId: 'example.com'),
      );
    });

    _testUserNotMemberOfPublisher(
      testProfile: _profile(),
      fn: (client) async => client.setPackagePublisher(
        'one',
        PackagePublisherInfo(publisherId: 'example.com'),
      ),
    );

    _testUserNotAdminOfPublisher(
      testProfile: _profile(),
      fn: (client) async => client.setPackagePublisher(
        'one',
        PackagePublisherInfo(publisherId: 'example.com'),
      ),
    );

    testWithProfile('successful', testProfile: _profile(), fn: () async {
      final client = createPubApiClient(authToken: adminAtPubDevAuthToken);
      final rs = await client.setPackagePublisher(
        'one',
        PackagePublisherInfo(publisherId: 'example.com'),
      );
      expect(_json(rs.toJson()), {'publisherId': 'example.com'});

      final p = (await packageBackend.lookupPackage('one'))!;
      expect(p.publisherId, 'example.com');
      expect(p.uploaders, []);

      final info = await client.getPackagePublisher('one');
      expect(_json(info.toJson()), _json(rs.toJson()));
    });
  });

  group('Delete publisher', () {
    _testNoPackage((client) async {
      return client.removePackagePublisher('no_package');
    });

    _testNoActiveUser((client) async {
      return client.removePackagePublisher('oxygen');
    });

    _testUserNotMemberOfPublisher(
      fn: (client) => client.removePackagePublisher('neon'),
    );

    _testUserNotAdminOfPublisher(
      fn: (client) => client.removePackagePublisher('neon'),
    );

    testWithProfile('successful', fn: () async {
      final client = createPubApiClient(authToken: adminAtPubDevAuthToken);
      final rs = client.removePackagePublisher('neon');
      await expectApiException(rs, status: 501);
//  Code commented out while we decide if this feature is something we want to
//  support going forward.
//
//      final rs = await client.removePackagePublisher('neon');
//      expect(_json(rs.toJson()), {'publisherId': null});
//
//      final p = await packageBackend.lookupPackage('neon');
//      expect(p.publisherId, isNull);
//      expect(p.uploaders, isNotEmpty);
//
//      final info = await client.getPackagePublisher('neon');
//      expect(_json(info.toJson()), _json(rs.toJson()));
    });
  });
}

dynamic _json(value) => json.decode(json.encode(value));

void _testUserNotMemberOfPublisher({
  required Future<void> Function(PubApiClient client) fn,
  String authToken = 'other-at-pub-dot-dev',
  TestProfile? testProfile,
}) {
  testWithProfile('Active user is not a member of publisher',
      testProfile: testProfile, fn: () async {
    final client = createPubApiClient(authToken: authToken);
    final rs = fn(client);
    await expectApiException(rs, status: 403, code: 'InsufficientPermissions');
  });
}

void _testUserNotAdminOfPublisher({
  required Future<void> Function(PubApiClient client) fn,
  String authToken = adminAtPubDevAuthToken,
  TestProfile? testProfile,
}) {
  testWithProfile('Active user is not admin of publisher',
      testProfile: testProfile, fn: () async {
    await accountBackend.withBearerToken(authToken, () async {
      final user = await requireAuthenticatedUser();
      final members = await dbService
          .query<PublisherMember>()
          .run()
          .where((e) => e.userId == user.userId)
          .toList();
      expect(members, isNotEmpty);
      for (final m in members) {
        m.role = 'non-admin';
      }
      await dbService.commit(inserts: members);
    });
    final client = createPubApiClient(authToken: authToken);
    final rs = fn(client);
    await expectApiException(rs, status: 403, code: 'InsufficientPermissions');
  });
}

void _testNoActiveUser(Future Function(PubApiClient client) fn) {
  testWithProfile('No active user', fn: () async {
    final client = createPubApiClient();
    final rs = fn(client);
    await expectApiException(rs,
        status: 401,
        code: 'MissingAuthentication',
        message: 'please add `authorization` header');
  });
}

void _testNoPackage(Future Function(PubApiClient client) fn) {
  testWithProfile('No package with given name', fn: () async {
    final client = createPubApiClient(authToken: adminAtPubDevAuthToken);
    final rs = fn(client);
    await expectApiException(rs, status: 404, code: 'NotFound');
  });
}

void _testNoPublisher(Future Function(PubApiClient client) fn) {
  testWithProfile('No publisher with given id', fn: () async {
    final client = createPubApiClient(authToken: adminAtPubDevAuthToken);
    final rs = fn(client);
    await expectApiException(rs, status: 404, code: 'NotFound');
  });
}
