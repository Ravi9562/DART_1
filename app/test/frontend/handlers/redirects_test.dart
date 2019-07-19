// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_dartlang_org/shared/search_service.dart';
import 'package:test/test.dart';

import 'package:pub_dartlang_org/frontend/handlers/redirects.dart';
import 'package:pub_dartlang_org/frontend/search_service.dart';
import 'package:pub_dartlang_org/frontend/static_files.dart';
import 'package:pub_dartlang_org/shared/urls.dart';

import '../../shared/handlers_test_utils.dart';

import '_utils.dart';

void main() {
  setUpAll(() => updateLocalBuiltFiles());

  group('redirects', () {
    test('pub.dartlang.org', () async {
      Future testRedirect(String path) async {
        expectRedirectResponse(
            await issueGet(path, host: 'pub.dartlang.org'), '$siteRoot$path');
      }

      testRedirect('/');
      testRedirect('/packages');
      testRedirect('/packages/pana');
      testRedirect('/flutter');
      testRedirect('/web');
    });

    test('dartdocs.org redirect', () async {
      expectRedirectResponse(
        await issueGet('/documentation/pkg/latest/', host: 'dartdocs.org'),
        '$siteRoot/documentation/pkg/latest/',
      );
    });

    test('www.dartdocs.org redirect', () async {
      expectRedirectResponse(
        await issueGet('/documentation/pkg/latest/', host: 'www.dartdocs.org'),
        '$siteRoot/documentation/pkg/latest/',
      );
    });

    tScopedTest('/doc', () async {
      registerSearchService(SearchServiceMock());
      for (var path in redirectPaths.keys) {
        final redirectUrl = 'https://dart.dev/tools/pub/${redirectPaths[path]}';
        expectNotFoundResponse(await issueGet(path));
        expectRedirectResponse(
            await issueGet(path, host: 'pub.dartlang.org'), redirectUrl);
      }
    });

    // making sure /doc does not catches /documentation request
    tScopedTest('/documentation', () async {
      expectRedirectResponse(await issueGet('/documentation/pana/'),
          '/documentation/pana/latest/');
    });

    tScopedTest('/flutter/plugins', () async {
      registerSearchService(SearchServiceMock());
      expectRedirectResponse(
          await issueGet('/flutter/plugins', host: 'pub.dartlang.org'),
          'https://pub.dev/flutter/packages');
      expectNotFoundResponse(await issueGet('/flutter/plugins'));
    });

    tScopedTest('/search?q=foobar', () async {
      registerSearchService(SearchServiceMock());
      expectRedirectResponse(
          await issueGet('/search?q=foobar', host: 'pub.dartlang.org'),
          '$siteRoot/packages?q=foobar');
      expectNotFoundResponse(await issueGet('/search?q=foobar'));
    });

    tScopedTest('/search?q=foobar&page=2', () async {
      registerSearchService(SearchServiceMock());
      expectRedirectResponse(
          await issueGet('/search?q=foobar&page=2', host: 'pub.dartlang.org'),
          '$siteRoot/packages?q=foobar&page=2');
      expectNotFoundResponse(await issueGet('/search?q=foobar&page=2'));
    });

    tScopedTest('/server', () async {
      registerSearchService(SearchServiceMock());
      expectRedirectResponse(
          await issueGet('/server', host: 'pub.dartlang.org'), '$siteRoot/');
      expectNotFoundResponse(await issueGet('/server'));
    });

    tScopedTest('/server/packages with parameters', () async {
      registerSearchService(SearchServiceMock());
      expectRedirectResponse(
          await issueGet('/server/packages?sort=top', host: 'pub.dartlang.org'),
          '$siteRoot/packages?sort=top');
      expectNotFoundResponse(await issueGet('/server/packages?sort=top'));
    });

    tScopedTest('/server/packages', () async {
      registerSearchService(SearchServiceMock());
      expectRedirectResponse(
          await issueGet('/server/packages', host: 'pub.dartlang.org'),
          '$siteRoot/packages');
      expectNotFoundResponse(await issueGet('/server/packages'));
    });

    tScopedTest('/packages/flutter - redirect', () async {
      expectRedirectResponse(
        await issueGet('/packages/flutter'),
        '$siteRoot/flutter',
      );
    });

    tScopedTest('/packages/flutter/versions/* - redirect', () async {
      expectRedirectResponse(
        await issueGet('/packages/flutter/versions/0.20'),
        '$siteRoot/flutter',
      );
    });
  });
}

class SearchServiceMock implements SearchService {
  @override
  Future<SearchResultPage> search(SearchQuery query,
      {bool fallbackToNames = true}) async {
    return SearchResultPage.empty(query);
  }

  @override
  Future close() async {
    return null;
  }
}
