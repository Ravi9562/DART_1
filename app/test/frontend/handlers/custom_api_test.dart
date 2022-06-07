// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:pub_dev/package/backend.dart';
import 'package:pub_dev/package/name_tracker.dart';
import 'package:pub_dev/shared/configuration.dart';
import 'package:pub_dev/shared/datastore.dart';
import 'package:pub_dev/shared/urls.dart' as urls;
import 'package:test/test.dart';

import '../../shared/handlers_test_utils.dart';
import '../../shared/test_services.dart';
import '_utils.dart';

void main() {
  group('editor api', () {
    testWithProfile('/api/packages', fn: () async {
      await expectJsonResponse(
        await issueGet('/api/packages', host: urls.legacyHost),
        body: {
          'next_url': null,
          'packages': [
            {
              'name': 'oxygen',
              'latest': {
                'version': '1.2.0',
                'pubspec': {
                  'name': 'oxygen',
                  'version': '1.2.0',
                  'description': 'oxygen is awesome',
                  'homepage': 'https://oxygen.example.dev/',
                  'environment': {'sdk': '>=2.6.0 <3.0.0'},
                  'dependencies': {},
                  'screenshots': [
                    {
                      'path': 'static.webp',
                      'description': 'This is an awesome screenshot'
                    }
                  ]
                },
                'archive_url':
                    '${activeConfiguration.primaryApiUri}/packages/oxygen/versions/1.2.0.tar.gz',
                'package_url':
                    '${activeConfiguration.primaryApiUri}/api/packages/oxygen',
                'url':
                    '${activeConfiguration.primaryApiUri}/api/packages/oxygen/versions/1.2.0'
              }
            },
            {
              'name': 'flutter_titanium',
              'latest': {
                'version': '1.10.0',
                'pubspec': {
                  'name': 'flutter_titanium',
                  'version': '1.10.0',
                  'description': 'flutter_titanium is awesome',
                  'homepage': 'https://flutter_titanium.example.dev/',
                  'environment': {'sdk': '>=2.6.0 <3.0.0'},
                  'dependencies': {
                    'flutter': {'sdk': 'flutter'}
                  },
                  'screenshots': [
                    {
                      'path': 'static.webp',
                      'description': 'This is an awesome screenshot'
                    }
                  ]
                },
                'archive_url':
                    '${activeConfiguration.primaryApiUri}/packages/flutter_titanium/versions/1.10.0.tar.gz',
                'package_url':
                    '${activeConfiguration.primaryApiUri}/api/packages/flutter_titanium',
                'url':
                    '${activeConfiguration.primaryApiUri}/api/packages/flutter_titanium/versions/1.10.0'
              }
            },
            {
              'name': 'neon',
              'latest': {
                'version': '1.0.0',
                'pubspec': {
                  'name': 'neon',
                  'version': '1.0.0',
                  'description': 'neon is awesome',
                  'homepage': 'https://neon.example.dev/',
                  'environment': {'sdk': '>=2.6.0 <3.0.0'},
                  'dependencies': {},
                  'screenshots': [
                    {
                      'path': 'static.webp',
                      'description': 'This is an awesome screenshot'
                    }
                  ]
                },
                'archive_url':
                    '${activeConfiguration.primaryApiUri}/packages/neon/versions/1.0.0.tar.gz',
                'package_url':
                    '${activeConfiguration.primaryApiUri}/api/packages/neon',
                'url':
                    '${activeConfiguration.primaryApiUri}/api/packages/neon/versions/1.0.0'
              }
            }
          ]
        },
      );
    });

    testWithProfile('/api/package-names', fn: () async {
      await expectJsonResponse(
        await issueGet('/api/package-names'),
        body: {
          'packages': containsAll([
            'neon',
            'oxygen',
          ]),
          'nextUrl': null,
        },
      );
    });

    testWithProfile('/api/package-names - only valid packages', fn: () async {
      await expectJsonResponse(
        await issueGet('/api/package-names'),
        body: {
          'packages': contains('neon'),
          'nextUrl': null,
        },
      );
      final p = await packageBackend.lookupPackage('neon');
      p!.updateIsBlocked(isBlocked: true, reason: 'spam');
      expect(p.isVisible, isFalse);
      await dbService.commit(inserts: [p]);
      await nameTracker.scanDatastore();
      await expectJsonResponse(
        await issueGet('/api/package-names'),
        body: {
          'packages': isNot(contains('neon')),
          'nextUrl': null,
        },
      );
    });
  });

  group('score API', () {
    testWithProfile(
      '/api/packages/<package>/score endpoint',
      processJobsWithFakeRunners: true,
      fn: () async {
        final rs = await issueGet('/api/packages/oxygen/score');
        final map = json.decode(await rs.readAsString());
        expect(map, {
          'grantedPoints': greaterThan(10),
          'maxPoints': greaterThan(50),
          'likeCount': 0,
          'popularityScore': greaterThan(0),
          'tags': contains('sdk:dart'),
          'lastUpdated': isNotEmpty,
        });
      },
    );
  });
}
