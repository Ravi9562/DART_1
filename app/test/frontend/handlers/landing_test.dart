// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:http/testing.dart';
import 'package:pub_dev/frontend/static_files.dart';
import 'package:pub_dev/search/search_client.dart';
import 'package:test/test.dart';

import '../../shared/handlers_test_utils.dart';
import '../../shared/test_services.dart';
import '_utils.dart';

void main() {
  setUpAll(() => updateLocalBuiltFilesIfNeeded());

  group('ui', () {
    testWithProfile('/', fn: () async {
      final rs = await issueGet('/');
      await expectHtmlResponse(
        rs,
        present: [
          '/packages/oxygen',
          '/packages/neon',
          'oxygen is awesome',
        ],
        absent: [
          '/packages/http',
          '/packages/event_bus',
          'lightweight library for parsing',
        ],
      );
    });

    testWithProfile('/ without a working search service', fn: () async {
      registerSearchClient(
          SearchClient(MockClient((_) async => throw Exception())));
      final rs = await issueGet('/');
      await expectHtmlResponse(
        rs,
        present: [
          'The official package repository for',
        ],
        absent: [
          '/packages/neon',
          '/packages/oxygen',
          'Awesome package',
        ],
      );
    });

    testWithProfile('/flutter', fn: () async {
      final rs = await issueGet('/flutter');
      await expectRedirectResponse(rs, '/packages?q=sdk%3Aflutter');
    });

    testWithProfile('/xxx - not found page', fn: () async {
      final rs = await issueGet('/xxx');
      await expectHtmlResponse(rs, status: 404, present: [
        'You\'ve stumbled onto a page',
      ], absent: [
        '/packages/http',
        '/packages/event_bus',
        'lightweight library for parsing',
        '/packages/neon',
        '/packages/oxygen',
        'Awesome package',
      ]);
    });
  });

  group('static root paths', () {
    for (final path in staticRootPaths) {
      testWithProfile('/$path', fn: () async {
        final rs = await issueGet('/$path');
        expect(rs.statusCode, 200);
        // Reading the content to faster close of the stream.
        expect(await rs.read().toList(), isNotEmpty);
      });
    }
    testWithProfile('/osd.xml content check', fn: () async {
      final rs = await issueGet('/osd.xml');
      expect(rs.statusCode, 200);
      expect(await rs.readAsString(), contains('OpenSearchDescription'));
    });
  });
}
