// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_dartlang_org.handlers_test;

import 'dart:async';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'package:pub_dartlang_org/frontend/backend.dart';
import 'package:pub_dartlang_org/frontend/handlers_redirects.dart';
import 'package:pub_dartlang_org/frontend/models.dart';
import 'package:pub_dartlang_org/frontend/search_service.dart';
import 'package:pub_dartlang_org/frontend/templates.dart';
import 'package:pub_dartlang_org/shared/analyzer_client.dart';
import 'package:pub_dartlang_org/shared/dartdoc_client.dart';
import 'package:pub_dartlang_org/shared/search_service.dart';

import '../shared/handlers_test_utils.dart';
import '../shared/utils.dart';

import 'handlers_test_utils.dart';
import 'utils.dart';

void tScopedTest(String name, Future func()) {
  scopedTest(name, () {
    registerTemplateService(new TemplateMock());
    return func();
  });
}

void main() {
  final PageSize = 10;

  group('handlers', () {
    group('not found', () {
      tScopedTest('/xxx', () async {
        await expectNotFoundResponse(await issueGet('/xxx'));
      });
    });

    group('ui', () {
      tScopedTest('/', () async {
        registerSearchService(new SearchServiceMock((SearchQuery query) {
          expect(query.order, isNull);
          expect(query.offset, 0);
          expect(query.limit, 15);
          expect(query.platformPredicate, isNull);
          expect(query.query, isNull);
          return new SearchResultPage(
            query,
            1,
            [new PackageView.fromModel(version: testPackageVersion)],
          );
        }));
        final backend =
            new BackendMock(latestPackageVersionsFun: ({offset, limit}) {
          expect(offset, isNull);
          expect(limit, equals(5));
          return [testPackageVersion];
        });
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());

        await expectHtmlResponse(await issueGet('/'));
      });

      tScopedTest('/packages', () async {
        registerSearchService(new SearchServiceMock(
          (SearchQuery query) {
            expect(query.offset, 0);
            expect(query.limit, PageSize);
            expect(query.platformPredicate, isNull);
            return new SearchResultPage(query, 1, [
              new PackageView.fromModel(
                  package: testPackage,
                  version: testPackageVersion,
                  analysis: null)
            ]);
          },
        ));
        final backend = new BackendMock(
          lookupPackageFun: (packageName) {
            return packageName == testPackage.name ? testPackage : null;
          },
          lookupLatestVersionsFun: (List<Package> packages) {
            expect(packages.length, 1);
            expect(packages.first, testPackage);
            return [testPackageVersion];
          },
        );
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());
        await expectHtmlResponse(await issueGet('/packages'));
      });

      tScopedTest('/packages?q=foobar', () async {
        registerSearchService(new SearchServiceMock(
          (SearchQuery query) {
            expect(query.query, 'foobar');
            expect(query.offset, 0);
            expect(query.limit, PageSize);
            expect(query.platformPredicate, isNull);
            return new SearchResultPage(query, 1, [
              new PackageView.fromModel(
                  package: testPackage,
                  version: testPackageVersion,
                  analysis: null)
            ]);
          },
        ));
        final backend = new BackendMock(
          lookupPackageFun: (packageName) {
            return packageName == testPackage.name ? testPackage : null;
          },
          lookupLatestVersionsFun: (List<Package> packages) {
            expect(packages.length, 1);
            expect(packages.first, testPackage);
            return [testPackageVersion];
          },
        );
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());
        await expectHtmlResponse(await issueGet('/packages?q=foobar'));
      });

      tScopedTest('/packages?page=2', () async {
        registerSearchService(new SearchServiceMock(
          (SearchQuery query) {
            expect(query.offset, 10);
            expect(query.limit, PageSize);
            expect(query.platformPredicate, isNull);
            return new SearchResultPage(query, 1, [
              new PackageView.fromModel(
                  package: testPackage,
                  version: testPackageVersion,
                  analysis: null)
            ]);
          },
        ));
        final backend = new BackendMock(
          lookupPackageFun: (packageName) {
            return packageName == testPackage.name ? testPackage : null;
          },
          lookupLatestVersionsFun: (List<Package> packages) {
            expect(packages.length, 1);
            expect(packages.first, testPackage);
            return [testPackageVersion];
          },
        );
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());
        await expectHtmlResponse(await issueGet('/packages?page=2'));
      });

      tScopedTest('/packages/foobar_pkg - found', () async {
        final backend = new BackendMock(lookupPackageFun: (String packageName) {
          expect(packageName, 'foobar_pkg');
          return testPackage;
        }, versionsOfPackageFun: (String package) {
          expect(package, testPackage.name);
          return [testPackageVersion];
        }, downloadUrlFun: (String package, String version) {
          return Uri.parse('http://blobstore/$package/$version');
        });
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());
        registerDartdocClient(new DartdocClientMock());
        await expectHtmlResponse(await issueGet('/packages/foobar_pkg'));
      });

      tScopedTest('/packages/foobar_pkg - not found', () async {
        final backend = new BackendMock(lookupPackageFun: (String packageName) {
          expect(packageName, 'foobar_pkg');
          return null;
        });
        registerBackend(backend);
        await expectRedirectResponse(
            await issueGet('/packages/foobar_pkg'), '/packages?q=foobar_pkg');
      });

      tScopedTest('/packages/foobar_pkg/versions - found', () async {
        final backend = new BackendMock(versionsOfPackageFun: (String package) {
          expect(package, testPackage.name);
          return [testPackageVersion];
        }, downloadUrlFun: (String package, String version) {
          return Uri.parse('http://blobstore/$package/$version');
        });
        registerBackend(backend);
        registerDartdocClient(new DartdocClientMock());
        await expectHtmlResponse(
            await issueGet('/packages/foobar_pkg/versions'));
      });

      tScopedTest('/packages/foobar_pkg/versions - not found', () async {
        final backend = new BackendMock(versionsOfPackageFun: (String package) {
          expect(package, testPackage.name);
          return [];
        });
        registerBackend(backend);
        await expectRedirectResponse(
            await issueGet('/packages/foobar_pkg/versions'),
            '/packages?q=foobar_pkg');
      });

      tScopedTest('/packages/foobar_pkg/versions/0.1.1 - found', () async {
        final backend = new BackendMock(lookupPackageFun: (String package) {
          expect(package, testPackage.name);
          return testPackage;
        }, versionsOfPackageFun: (String package) {
          expect(package, testPackage.name);
          return [testPackageVersion];
        }, downloadUrlFun: (String package, String version) {
          return Uri.parse('http://blobstore/$package/$version');
        });
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());
        registerDartdocClient(new DartdocClientMock());
        await expectHtmlResponse(
            await issueGet('/packages/foobar_pkg/versions/0.1.1'));
      });

      tScopedTest('/packages/foobar_pkg/versions/0.1.2 - not found', () async {
        final backend = new BackendMock(lookupPackageFun: (String package) {
          expect(package, testPackage.name);
          return testPackage;
        }, versionsOfPackageFun: (String package) {
          expect(package, testPackage.name);
          return [testPackageVersion];
        }, downloadUrlFun: (String package, String version) {
          return Uri.parse('http://blobstore/$package/$version');
        });
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());
        registerDartdocClient(new DartdocClientMock());
        await expectRedirectResponse(
            await issueGet('/packages/foobar_pkg/versions/0.1.2'),
            '/packages/foobar_pkg#-versions-tab-');
      });

      tScopedTest('/packages/flutter - redirect', () async {
        expectRedirectResponse(
          await issueGet('/packages/flutter'),
          'https://pub.dartlang.org/flutter',
        );
      });

      tScopedTest('/packages/flutter/versions/* - redirect', () async {
        expectRedirectResponse(
          await issueGet('/packages/flutter/versions/0.20'),
          'https://pub.dartlang.org/flutter',
        );
      });

      tScopedTest('/flutter', () async {
        registerSearchService(new SearchServiceMock((SearchQuery query) {
          expect(query.order, isNull);
          expect(query.offset, 0);
          expect(query.limit, 15);
          expect(query.platformPredicate.single, 'flutter');
          expect(query.query, isNull);
          return new SearchResultPage(
            query,
            1,
            [new PackageView.fromModel(version: testPackageVersion)],
          );
        }));
        final backend =
            new BackendMock(latestPackageVersionsFun: ({offset, limit}) {
          expect(offset, isNull);
          expect(limit, equals(5));
          return [testPackageVersion];
        });
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());

        await expectHtmlResponse(await issueGet('/flutter'));
      });

      tScopedTest('/flutter/plugins', () async {
        expectRedirectResponse(
            await issueGet('/flutter/plugins'), '/flutter/packages');
      });

      tScopedTest('/flutter/packages', () async {
        registerSearchService(new SearchServiceMock(
          (SearchQuery query) {
            expect(query.offset, 0);
            expect(query.limit, PageSize);
            expect(query.platformPredicate.isNotEmpty, isTrue);
            expect(query.platformPredicate.single, 'flutter');
            return new SearchResultPage(query, 1, [
              new PackageView.fromModel(
                  package: testPackage,
                  version: testPackageVersion,
                  analysis: null)
            ]);
          },
        ));
        final backend = new BackendMock(
          lookupPackageFun: (packageName) {
            return packageName == testPackage.name ? testPackage : null;
          },
          lookupLatestVersionsFun: (List<Package> packages) {
            expect(packages.length, 1);
            expect(packages.first, testPackage);
            return [testPackageVersion];
          },
        );
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());
        await expectHtmlResponse(await issueGet('/flutter/packages'));
      });

      tScopedTest('/flutter/packages&page=2', () async {
        registerSearchService(new SearchServiceMock(
          (SearchQuery query) {
            expect(query.offset, 10);
            expect(query.limit, PageSize);
            expect(query.platformPredicate.isNotEmpty, isTrue);
            expect(query.platformPredicate.single, 'flutter');
            return new SearchResultPage(query, 1, [
              new PackageView.fromModel(
                  package: testPackage,
                  version: testPackageVersion,
                  analysis: null)
            ]);
          },
        ));
        final backend = new BackendMock(
          lookupPackageFun: (packageName) {
            return packageName == testPackage.name ? testPackage : null;
          },
          lookupLatestVersionsFun: (List<Package> packages) {
            expect(packages.length, 1);
            expect(packages.first, testPackage);
            return [testPackageVersion];
          },
        );
        registerBackend(backend);
        registerAnalyzerClient(new AnalyzerClientMock());
        await expectHtmlResponse(await issueGet('/flutter/packages?page=2'));
      });

      tScopedTest('/server', () async {
        expectRedirectResponse(await issueGet('/server'), '/');
      });

      tScopedTest('/server/packages with parameters', () async {
        expectRedirectResponse(
            await issueGet('/server/packages?sort=top'), '/packages?sort=top');
      });

      tScopedTest('/server/packages', () async {
        expectRedirectResponse(await issueGet('/server/packages'), '/packages');
      });

      tScopedTest('/doc', () async {
        for (var path in redirectPaths.keys) {
          final redirectUrl =
              'https://www.dartlang.org/tools/pub/${redirectPaths[path]}';
          expectRedirectResponse(await issueGet(path), redirectUrl);
        }
      });

      tScopedTest('/authorized', () async {
        await expectHtmlResponse(await issueGet('/authorized'));
      });

      tScopedTest('/search?q=foobar', () async {
        expectRedirectResponse(await issueGet('/search?q=foobar'),
            'https://pub.dartlang.org/packages?q=foobar');
      });

      tScopedTest('/search?q=foobar&page=2', () async {
        expectRedirectResponse(await issueGet('/search?q=foobar&page=2'),
            'https://pub.dartlang.org/packages?q=foobar&page=2');
      });

      tScopedTest('/feed.atom', () async {
        final backend =
            new BackendMock(latestPackageVersionsFun: ({offset, limit}) {
          expect(offset, 0);
          expect(limit, PageSize);
          return [testPackageVersion];
        });
        registerBackend(backend);
        await expectAtomXmlResponse(await issueGet('/feed.atom'), regexp: '''
<\\?xml version="1.0" encoding="UTF-8"\\?>
<feed xmlns="http://www.w3.org/2005/Atom">
        <id>https://pub.dartlang.org/feed.atom</id>
        <title>Pub Packages for Dart</title>
        <updated>(.*)</updated>
        <author>
          <name>Dart Team</name>
        </author>
        <link href="https://pub.dartlang.org/" rel="alternate" />
        <link href="https://pub.dartlang.org/feed.atom" rel="self" />
        <generator version="0.1.0">Pub Feed Generator</generator>
        <subtitle>Last Updated Packages</subtitle>
(\\s*)
        <entry>
          <id>urn:uuid:f38e70f0-13de-51b6-88b8-57430c66ce75</id>
          <title>v0.1.1 of foobar_pkg</title>
          <updated>${testPackageVersion.created.toIso8601String()}</updated>
          <author><name>Hans Juergen &lt;hans@juergen.com&gt;</name></author>
          <content type="html">&lt;h1&gt;Test Package&lt;&#47;h1&gt;
&lt;p&gt;This is a readme file.&lt;&#47;p&gt;
&lt;pre&gt;&lt;code class=&quot;language-dart&quot;&gt;void main\\(\\) {
}
&lt;&#47;code&gt;&lt;&#47;pre&gt;
</content>
          <link href="https://pub.dartlang.org/packages/foobar_pkg"
                rel="alternate"
                title="foobar_pkg" />
        </entry>
(\\s*)
</feed>
''');
      });
    });

    group('old api', () {
      scopedTest('/packages.json', () async {
        final backend =
            new BackendMock(latestPackagesFun: ({offset, limit, detectedType}) {
          expect(offset, 0);
          expect(limit, greaterThan(PageSize));
          return [testPackage];
        }, lookupLatestVersionsFun: (List<Package> packages) {
          expect(packages.length, 1);
          expect(packages.first, testPackage);
          return [testPackageVersion];
        });
        registerBackend(backend);
        await expectJsonResponse(await issueGet('/packages.json'), body: {
          "packages": ["https://pub.dartlang.org/packages/foobar_pkg.json"],
          "next": null
        });
      });

      tScopedTest('/packages/foobar_pkg.json', () async {
        final backend = new BackendMock(lookupPackageFun: (String package) {
          expect(package, 'foobar_pkg');
          return testPackage;
        }, versionsOfPackageFun: (String package) {
          expect(package, 'foobar_pkg');
          return [testPackageVersion];
        });
        registerBackend(backend);
        await expectJsonResponse(await issueGet('/packages/foobar_pkg.json'),
            body: {
              "name": 'foobar_pkg',
              "uploaders": ['hans@juergen.com'],
              "versions": ['0.1.1'],
            });
      });
    });

    group('editor api', () {
      tScopedTest('/api/packages', () async {
        final backend =
            new BackendMock(latestPackagesFun: ({offset, limit, detectedType}) {
          expect(offset, 0);
          expect(limit, greaterThan(10));
          return [testPackage];
        }, lookupLatestVersionsFun: (List<Package> packages) {
          expect(packages.length, 1);
          expect(packages.first, testPackage);
          return [testPackageVersion];
        });
        registerBackend(backend);
        await expectJsonResponse(await issueGet('/api/packages'), body: {
          'next_url': null,
          'packages': [
            {
              'name': 'foobar_pkg',
              'latest': {
                'version': '0.1.1',
                'pubspec': loadYaml(TestPackagePubspec),
                'archive_url': 'https://pub.dartlang.org'
                    '/packages/foobar_pkg/versions/0.1.1.tar.gz',
                'package_url': 'https://pub.dartlang.org'
                    '/api/packages/foobar_pkg',
                'url': 'https://pub.dartlang.org'
                    '/api/packages/foobar_pkg/versions/0.1.1'
              },
              'url': 'https://pub.dartlang.org/api/packages/foobar_pkg',
              'version_url': 'https://pub.dartlang.org'
                  '/api/packages/foobar_pkg/versions/%7Bversion%7D',
              'new_version_url': 'https://pub.dartlang.org'
                  '/api/packages/foobar_pkg/new',
              'uploaders_url': 'https://pub.dartlang.org'
                  '/api/packages/foobar_pkg/uploaders'
            }
          ]
        });
      });
    });
  });
}
