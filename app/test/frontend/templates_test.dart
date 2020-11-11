// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart';
import 'package:pana/pana.dart' hide ReportStatus;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart' as xml;

import 'package:pub_dev/account/models.dart';
import 'package:pub_dev/analyzer/analyzer_client.dart';
import 'package:pub_dev/dartdoc/models.dart';
import 'package:pub_dev/frontend/static_files.dart';
import 'package:pub_dev/frontend/templates/admin.dart';
import 'package:pub_dev/frontend/templates/landing.dart';
import 'package:pub_dev/frontend/templates/layout.dart';
import 'package:pub_dev/frontend/templates/listing.dart';
import 'package:pub_dev/frontend/templates/misc.dart';
import 'package:pub_dev/frontend/templates/package.dart';
import 'package:pub_dev/frontend/templates/package_admin.dart';
import 'package:pub_dev/frontend/templates/package_analysis.dart';
import 'package:pub_dev/frontend/templates/package_versions.dart';
import 'package:pub_dev/frontend/templates/publisher.dart';
import 'package:pub_dev/package/models.dart';
import 'package:pub_dev/publisher/models.dart';
import 'package:pub_dev/scorecard/models.dart';
import 'package:pub_dev/search/search_form.dart';
import 'package:pub_dev/search/search_service.dart';
import 'package:pub_dev/shared/versions.dart';
import 'package:pub_dev/tool/html/html_validation.dart';

import '../shared/test_models.dart';
import '../shared/utils.dart';

const String goldenDir = 'test/frontend/golden';

final _regenerateGoldens = false;

void main() {
  setUpAll(() => updateLocalBuiltFilesIfNeeded());

  group('templates', () {
    StaticFileCache oldCache;

    setUpAll(() {
      final properCache = StaticFileCache.withDefaults();
      final cache = StaticFileCache();
      for (String path in properCache.keys) {
        final file = StaticFile(path, 'text/mock', [], DateTime.now(),
            'mocked_hash_${path.hashCode.abs()}');
        cache.addFile(file);
      }
      oldCache = staticFileCache;
      registerStaticFileCacheForTest(cache);
    });

    tearDownAll(() {
      registerStaticFileCacheForTest(oldCache);
    });

    void expectGoldenFile(String content, String fileName,
        {bool isFragment = false}) {
      // Making sure it is valid HTML
      final htmlParser = HtmlParser(content, strict: true);

      if (isFragment) {
        final root = htmlParser.parseFragment();
        validateHtml(root);
      } else {
        final root = htmlParser.parse();
        validateHtml(root);
      }

      // Pretty printing output using XML parser and formatter.
      final xmlDoc = xml.XmlDocument.parse(
        isFragment ? '<fragment>' + content + '</fragment>' : content,
        entityMapping: xml.XmlDefaultEntityMapping.html5(),
      );
      final xmlContent = xmlDoc.toXmlString(
            pretty: true,
            indent: '  ',
            entityMapping: xml.XmlDefaultEntityMapping.html5(),
          ) +
          '\n';

      if (_regenerateGoldens) {
        File('$goldenDir/$fileName').writeAsStringSync(xmlContent);
        fail('Set `_regenerateGoldens` to `false` to run tests.');
      }
      final golden = File('$goldenDir/$fileName').readAsStringSync();
      expect(xmlContent.split('\n'), golden.split('\n'));
    }

    scopedTest('landing page', () {
      final String html = renderLandingPage(ffPackages: [
        PackageView.fromModel(
          package: foobarPackage,
          version: foobarStablePV,
          scoreCard: ScoreCardData(
            derivedTags: [
              'sdk:flutter',
              'platform:android',
              'is:flutter-favorite',
            ],
            reportTypes: ['pana'],
          ),
        ),
      ], mostPopularPackages: [
        PackageView.fromModel(
          package: foobarPackage,
          version: foobarStablePV,
          scoreCard: ScoreCardData(
            derivedTags: [
              'sdk:flutter',
              'platform:android',
              'is:flutter-favorite',
            ],
            reportTypes: ['pana'],
          ),
        ),
        PackageView.fromModel(
          package: helium.package,
          version: helium.latestStableVersion,
          scoreCard: ScoreCardData(
            derivedTags: [
              'sdk:dart',
              'runtime:native',
            ],
            reportTypes: ['pana'],
          ),
        ),
      ]);
      expectGoldenFile(html, 'landing_page.html');
    });

    PackagePageData foobarPageDataFn({String assetKind}) => PackagePageData(
          package: foobarPackage,
          isLiked: false,
          uploaderEmails: foobarUploaderEmails,
          version: foobarStablePV,
          versionInfo: pvToInfo(foobarStablePV),
          asset:
              assetKind == null ? null : pvToAsset(foobarStablePV, assetKind),
          analysis: AnalysisView(
            card: ScoreCardData(
              reportTypes: ['pana', 'dartdoc'],
            ),
            panaReport: PanaReport(
                timestamp: DateTime(2018, 02, 05),
                panaRuntimeInfo: _panaRuntimeInfo,
                reportStatus: ReportStatus.success,
                derivedTags: null,
                pkgDependencies: [
                  PkgDependency(
                    package: 'quiver',
                    dependencyType: 'direct',
                    constraintType: 'normal',
                    constraint: VersionConstraint.parse('^1.0.0'),
                    resolved: Version.parse('1.0.0'),
                    available: null,
                    errors: null,
                  ),
                  PkgDependency(
                    package: 'http',
                    dependencyType: 'direct',
                    constraintType: 'normal',
                    constraint: VersionConstraint.parse('>=1.0.0 <1.2.0'),
                    resolved: Version.parse('1.2.0'),
                    available: Version.parse('1.3.0'),
                    errors: null,
                  )
                ],
                licenseFile: LicenseFile('LICENSE.txt', 'BSD'),
                report: Report(sections: <ReportSection>[]),
                flags: null),
            dartdocReport: DartdocReport(
              reportStatus: ReportStatus.success,
              dartdocEntry: DartdocEntry(
                uuid: '1234-5678-dartdocentry-90ab',
                packageName: foobarPkgName,
                packageVersion: foobarStableVersion,
                isLatest: true,
                isObsolete: false,
                usesFlutter: false,
                runtimeVersion: runtimeVersion,
                sdkVersion: _panaRuntimeInfo.sdkVersion,
                dartdocVersion: dartdocVersion,
                flutterVersion: null,
                timestamp: DateTime(2018, 02, 05),
                depsResolved: true,
                hasContent: true,
                archiveSize: 101023,
                totalSize: 203045,
              ),
              documentationSection:
                  documentationCoverageSection(documented: 17, total: 17),
            ),
          ),
          isAdmin: true,
        );

    scopedTest('package show page', () {
      final String html =
          renderPkgShowPage(foobarPageDataFn(assetKind: AssetKind.readme));
      expectGoldenFile(html, 'pkg_show_page.html');
    });

    scopedTest('package changelog page', () {
      final String html = renderPkgChangelogPage(
          foobarPageDataFn(assetKind: AssetKind.changelog));
      expectGoldenFile(html, 'pkg_changelog_page.html');
    });

    scopedTest('package example page', () {
      final String html =
          renderPkgExamplePage(foobarPageDataFn(assetKind: AssetKind.example));
      expectGoldenFile(html, 'pkg_example_page.html');
    });

    scopedTest('package install page', () {
      final String html = renderPkgInstallPage(foobarPageDataFn());
      expectGoldenFile(html, 'pkg_install_page.html');
    });

    scopedTest('package score page', () {
      final String html = renderPkgScorePage(foobarPageDataFn());
      expectGoldenFile(html, 'pkg_score_page.html');
    });

    scopedTest('package show page - with version', () {
      final String html = renderPkgShowPage(PackagePageData(
        package: foobarPackage,
        isLiked: false,
        uploaderEmails: foobarUploaderEmails,
        version: foobarDevPV,
        versionInfo: pvToInfo(foobarDevPV),
        asset: pvToAsset(foobarDevPV, AssetKind.readme),
        analysis: AnalysisView(
          card: ScoreCardData(reportTypes: ['pana']),
          panaReport: PanaReport(
              timestamp: DateTime(2018, 02, 05),
              panaRuntimeInfo: _panaRuntimeInfo,
              reportStatus: ReportStatus.success,
              derivedTags: null,
              pkgDependencies: [
                PkgDependency(
                  package: 'quiver',
                  dependencyType: 'direct',
                  constraintType: 'normal',
                  constraint: VersionConstraint.parse('^1.0.0'),
                  resolved: Version.parse('1.0.0'),
                  available: null,
                  errors: null,
                ),
                PkgDependency(
                  package: 'http',
                  dependencyType: 'direct',
                  constraintType: 'normal',
                  constraint: VersionConstraint.parse('>=1.0.0 <1.2.0'),
                  resolved: Version.parse('1.2.0'),
                  available: Version.parse('1.3.0'),
                  errors: null,
                )
              ],
              licenseFile: LicenseFile('LICENSE.txt', 'BSD'),
              report: Report(sections: <ReportSection>[]),
              flags: null),
          dartdocReport: null,
        ),
        isAdmin: true,
      ));
      expectGoldenFile(html, 'pkg_show_version_page.html');
    });

    scopedTest('package show page with flutter_plugin', () {
      final String html = renderPkgShowPage(PackagePageData(
        package: foobarPackage,
        isLiked: false,
        uploaderEmails: foobarUploaderEmails,
        version: flutterPackageVersion,
        versionInfo: pvToInfo(flutterPackageVersion),
        asset: pvToAsset(flutterPackageVersion, AssetKind.readme),
        analysis: AnalysisView(
          card: ScoreCardData(
            popularityScore: 0.3,
            derivedTags: ['sdk:flutter', 'platform:android'],
            flags: [PackageFlags.usesFlutter],
            reportTypes: ['pana'],
          ),
          panaReport: PanaReport(
              timestamp: DateTime(2018, 02, 05),
              panaRuntimeInfo: _panaRuntimeInfo,
              reportStatus: ReportStatus.success,
              derivedTags: ['sdk:flutter', 'platform:android'],
              pkgDependencies: null,
              licenseFile: null,
              report: Report(sections: <ReportSection>[]),
              flags: null),
        ),
        isAdmin: true,
      ));
      expectGoldenFile(html, 'pkg_show_page_flutter_plugin.html');
    });

    scopedTest('package show page with outdated version', () {
      final String html = renderPkgShowPage(PackagePageData(
        package: foobarPackage,
        isLiked: false,
        uploaderEmails: foobarUploaderEmails,
        version: foobarStablePV,
        versionInfo: pvToInfo(foobarStablePV),
        asset: pvToAsset(foobarStablePV, AssetKind.readme),
        analysis: AnalysisView(
          card: ScoreCardData(
            flags: [PackageFlags.isObsolete],
            updated: DateTime(2018, 02, 05),
          ),
        ),
        isAdmin: false,
      ));

      expectGoldenFile(html, 'pkg_show_page_outdated.html');
    });

    scopedTest('package show page with discontinued version', () {
      final String html = renderPkgShowPage(PackagePageData(
        package: discontinuedPackage,
        isLiked: false,
        uploaderEmails: foobarUploaderEmails,
        version: foobarStablePV,
        versionInfo: pvToInfo(foobarStablePV),
        asset: pvToAsset(foobarStablePV, AssetKind.readme),
        analysis: AnalysisView(
          card: ScoreCardData(
            flags: [PackageFlags.isDiscontinued],
            updated: DateTime(2018, 02, 05),
          ),
        ),
        isAdmin: false,
      ));

      expectGoldenFile(html, 'pkg_show_page_discontinued.html');
    });

    scopedTest('package show page with legacy version', () {
      final String html = renderPkgShowPage(PackagePageData(
        package: foobarPackage,
        isLiked: false,
        uploaderEmails: <String>[
          hansUser.email,
          joeUser.email,
        ],
        version: foobarStablePV,
        versionInfo: pvToInfo(foobarStablePV),
        asset: pvToAsset(foobarStablePV, AssetKind.readme),
        analysis: AnalysisView(
          card: ScoreCardData(
            popularityScore: 0.5,
            flags: [PackageFlags.isLegacy],
          ),
        ),
        isAdmin: false,
      ));

      expectGoldenFile(html, 'pkg_show_page_legacy.html');
    });

    scopedTest('package show page with publisher', () {
      final String html = renderPkgShowPage(PackagePageData(
        package: lithium.package,
        isLiked: false,
        uploaderEmails: <String>[],
        version: lithium.versions.last,
        versionInfo: pvToInfo(lithium.versions.last),
        asset: pvToAsset(lithium.versions.last, AssetKind.readme),
        analysis: AnalysisView(
          card: ScoreCardData(
            updated: DateTime(2018, 02, 05),
          ),
        ),
        isAdmin: false,
      ));

      expectGoldenFile(html, 'pkg_show_page_publisher.html');
    });

    scopedTest('no content for analysis tab', () async {
      // no content
      expect(renderAnalysisTab('pkg_foo', null, null, null, likeCount: 4),
          '<i>Awaiting analysis to complete.</i>');
    });

    scopedTest('analysis tab: http', () async {
      // stored analysis of http
      final String content =
          await File('$goldenDir/analysis_tab_http.json').readAsString();
      final map = json.decode(content) as Map<String, dynamic>;
      final card =
          ScoreCardData.fromJson(map['scorecard'] as Map<String, dynamic>);
      final reports = map['reports'] as Map<String, dynamic>;
      final panaReport =
          PanaReport.fromJson(reports['pana'] as Map<String, dynamic>);
      final view = AnalysisView(card: card, panaReport: panaReport);
      final String html = renderAnalysisTab(
        'http',
        '>=1.23.0-dev.0.0 <2.0.0',
        card,
        view,
        likeCount: 0,
      );
      expectGoldenFile(html, 'analysis_tab_http.html', isFragment: true);
    });

    scopedTest('mock analysis tab', () async {
      final card = ScoreCardData(
        popularityScore: 0.2323232,
        derivedTags: ['sdk:dart', 'runtime:web'],
        reportTypes: ['pana'],
      );
      final analysisView = AnalysisView(
        card: card,
        panaReport: PanaReport(
            timestamp: DateTime.utc(2017, 10, 26, 14, 03, 06),
            panaRuntimeInfo: _panaRuntimeInfo,
            reportStatus: ReportStatus.failed,
            derivedTags: card.derivedTags,
            pkgDependencies: [
              PkgDependency(
                package: 'http',
                dependencyType: 'direct',
                constraintType: 'normal',
                constraint: VersionConstraint.parse('^1.0.0'),
                resolved: Version.parse('1.0.0'),
                available: Version.parse('1.1.0'),
                errors: null,
              ),
              PkgDependency(
                package: 'async',
                dependencyType: 'transitive',
                constraintType: 'normal',
                constraint: VersionConstraint.parse('>=0.3.0 <1.0.0'),
                resolved: Version.parse('0.5.1'),
                available: Version.parse('1.0.2'),
                errors: null,
              ),
            ],
            licenseFile: null,
            report: Report(sections: <ReportSection>[]),
            flags: null),
      );
      final String html = renderAnalysisTab(
        'pkg_foo',
        '>=1.25.0-dev.9.0 <2.0.0',
        card,
        analysisView,
        likeCount: 2000,
      );
      expectGoldenFile(html, 'analysis_tab_mock.html', isFragment: true);
    });

    scopedTest('aborted analysis tab', () async {
      final String html = renderAnalysisTab(
        'pkg_foo',
        null,
        ScoreCardData(),
        AnalysisView(
          card: ScoreCardData(
            reportTypes: ['pana'],
          ),
          panaReport: PanaReport(
            timestamp: DateTime(2017, 12, 18, 14, 26, 00),
            panaRuntimeInfo: _panaRuntimeInfo,
            reportStatus: ReportStatus.aborted,
            derivedTags: null,
            pkgDependencies: null,
            licenseFile: null,
            report: Report(sections: <ReportSection>[]),
            flags: null,
          ),
        ),
        likeCount: 1000000,
      );

      expectGoldenFile(html, 'analysis_tab_aborted.html', isFragment: true);
    });

    scopedTest('outdated analysis tab', () async {
      final String html = renderAnalysisTab(
        'pkg_foo',
        null,
        ScoreCardData(flags: [PackageFlags.isObsolete]),
        AnalysisView(
          card: ScoreCardData(
            flags: [PackageFlags.isObsolete],
            updated: DateTime(2017, 12, 18, 14, 26, 00),
          ),
        ),
        likeCount: 1111,
      );
      expectGoldenFile(html, 'analysis_tab_outdated.html', isFragment: true);
    });

    scopedTest('package admin page with outdated version', () {
      final String html = renderPkgAdminPage(
        PackagePageData(
          package: foobarPackage,
          uploaderEmails: foobarUploaderEmails,
          version: foobarStablePV,
          versionInfo: pvToInfo(foobarStablePV),
          asset: null,
          analysis: AnalysisView(
            card: ScoreCardData(
              flags: [PackageFlags.isObsolete],
              updated: DateTime(2018, 02, 05),
            ),
          ),
          isLiked: false,
          isAdmin: true,
        ),
        [
          'example.com',
        ],
      );
      expectGoldenFile(html, 'pkg_admin_page_outdated.html');
    });

    scopedTest('package index page', () {
      final String html = renderPkgIndexPage(
        [
          PackageView.fromModel(
            package: foobarPackage,
            version: foobarStablePV,
            scoreCard: ScoreCardData(),
          ),
          PackageView.fromModel(
            package: foobarPackage,
            version: flutterPackageVersion,
            scoreCard: ScoreCardData(
              derivedTags: ['sdk:flutter', 'platform:android'],
              reportTypes: ['pana'],
            ),
          ),
        ],
        PageLinks.empty(),
        searchForm: SearchForm.parse(),
      );
      expectGoldenFile(html, 'pkg_index_page.html');
    });

    scopedTest('package index page with search', () {
      final searchForm =
          SearchForm.parse(query: 'foobar', order: SearchOrder.top);
      final String html = renderPkgIndexPage(
        [
          PackageView.fromModel(
            package: foobarPackage,
            version: foobarStablePV,
            scoreCard: ScoreCardData(),
            apiPages: [
              ApiPageRef(path: 'some/some-library.html'),
              ApiPageRef(title: 'Class X', path: 'some/x-class.html'),
            ],
          ),
          PackageView.fromModel(
            package: foobarPackage,
            version: flutterPackageVersion,
            scoreCard: ScoreCardData(
              derivedTags: ['sdk:flutter', 'platform:android'],
              reportTypes: ['pana'],
            ),
          ),
        ],
        PageLinks(searchForm, 50),
        searchForm: searchForm,
        totalCount: 2,
      );
      expectGoldenFile(html, 'search_page.html');
    });

    scopedTest('package versions page', () {
      final String html = renderPkgVersionsPage(
        PackagePageData(
          package: foobarPackage,
          isLiked: false,
          uploaderEmails: foobarUploaderEmails,
          version: foobarStablePV,
          versionInfo: pvToInfo(foobarStablePV),
          asset: null,
          analysis: AnalysisView(
            card: ScoreCardData(
              derivedTags: ['sdk:dart', 'sdk:flutter'],
              popularityScore: 0.2,
            ),
          ),
          isAdmin: false,
        ),
        [
          foobarStablePV,
          foobarDevPV,
        ],
        [
          Uri.parse('https://pub.dartlang.org/mock-download-uri.tar.gz'),
          Uri.parse('https://pub.dartlang.org/mock-download-uri.tar.gz'),
        ],
      );
      expectGoldenFile(html, 'pkg_versions_page.html');
    });

    scopedTest('publisher list page', () {
      final html = renderPublisherListPage(
        [
          PublisherSummary(
            publisherId: 'example.com',
            created: DateTime(2019, 09, 13),
          ),
          PublisherSummary(
            publisherId: 'other-domain.com',
            created: DateTime(2019, 09, 19),
          ),
        ],
      );
      expectGoldenFile(html, 'publisher_list_page.html');
    });

    scopedTest('publisher packages page', () {
      final searchForm = SearchForm.parse(publisherId: 'example.com');
      final html = renderPublisherPackagesPage(
        publisher: Publisher()
          ..id = 'example.com'
          ..contactEmail = 'hello@example.com'
          ..description = 'This is our little software developer shop.\n\n'
              'We develop full-stack in Dart, and happy about it.'
          ..websiteUrl = 'https://example.com/'
          ..created = DateTime(2019, 09, 13),
        packages: [
          PackageView(
            name: 'super_package',
            version: '1.0.0',
            ellipsizedDescription: 'A great web UI library.',
            created: DateTime.utc(2019, 01, 03),
            shortUpdated: '3 Jan 2019',
            tags: ['sdk:dart', 'runtime:web'],
          ),
          PackageView(
            name: 'another_package',
            version: '2.0.0',
            prereleaseVersion: '3.0.0-beta2',
            ellipsizedDescription: 'Camera plugin.',
            created: DateTime.utc(2019, 03, 30),
            shortUpdated: '30 Mar 2019',
            tags: ['sdk:flutter', 'platform:android'],
          ),
        ],
        totalCount: 2,
        searchForm: searchForm,
        pageLinks: PageLinks(searchForm, 10),
        isAdmin: true,
        messageFromBackend: null,
      );
      expectGoldenFile(html, 'publisher_packages_page.html');
    });

    scopedTest('/my-packages page', () {
      final searchForm =
          SearchForm.parse(uploaderOrPublishers: [hansUser.email]);
      final String html = renderAccountPackagesPage(
        user: hansUser,
        userSessionData: hansUserSessionData,
        packages: [
          PackageView(
            name: 'super_package',
            version: '1.0.0',
            ellipsizedDescription: 'A great web UI library.',
            created: DateTime.utc(2019, 01, 03),
            shortUpdated: '3 Jan 2019',
            tags: ['sdk:dart', 'runtime:web'],
          ),
          PackageView(
            name: 'another_package',
            version: '2.0.0',
            prereleaseVersion: '3.0.0-beta2',
            ellipsizedDescription: 'Camera plugin.',
            created: DateTime.utc(2019, 03, 30),
            shortUpdated: '30 Mar 2019',
            tags: ['sdk:flutter', 'platform:android'],
          ),
        ],
        pageLinks: PageLinks(searchForm, 10),
        searchForm: searchForm,
        totalCount: 2,
        messageFromBackend: null,
      );
      expectGoldenFile(html, 'my_packages.html');
    });

    scopedTest('/my-liked-packages page', () {
      final String html = renderMyLikedPackagesPage(
        user: hansUser,
        userSessionData: hansUserSessionData,
        likes: [
          LikeData(
              package: 'super_package',
              created: DateTime.fromMillisecondsSinceEpoch(1574423824000)),
          LikeData(
              package: 'another_package',
              created: DateTime.fromMillisecondsSinceEpoch(1574423824000))
        ],
      );
      expectGoldenFile(html, 'my_liked_packages.html');
    });

    scopedTest('/my-publishers page', () {
      final String html = renderAccountPublishersPage(
        user: hansUser,
        userSessionData: hansUserSessionData,
        publishers: [
          PublisherSummary(
            publisherId: exampleComPublisher.publisherId,
            created: exampleComPublisher.created,
          ),
        ],
      );
      expectGoldenFile(html, 'my_publishers.html');
    });

    scopedTest('authorized page', () {
      final String html = renderAuthorizedPage();
      expectGoldenFile(html, 'authorized_page.html');
    });

    scopedTest('error page', () {
      final String html = renderErrorPage('error_title', 'error_message');
      expectGoldenFile(html, 'error_page.html');
    });

    scopedTest('pagination: single page', () {
      final String html = renderPagination(PageLinks.empty());
      expectGoldenFile(html, 'pagination_single.html', isFragment: true);
    });

    scopedTest('pagination: in the middle', () {
      final String html =
          renderPagination(PageLinks(SearchForm.parse(currentPage: 10), 299));
      expectGoldenFile(html, 'pagination_middle.html', isFragment: true);
    });

    scopedTest('pagination: at first page', () {
      final String html = renderPagination(PageLinks(SearchForm.parse(), 600));
      expectGoldenFile(html, 'pagination_first.html', isFragment: true);
    });

    scopedTest('pagination: at last page', () {
      final String html =
          renderPagination(PageLinks(SearchForm.parse(currentPage: 10), 91));
      expectGoldenFile(html, 'pagination_last.html', isFragment: true);
    });

    scopedTest('platform tabs: list', () {
      final String html = renderSdkTabs();
      expectGoldenFile(html, 'platform_tabs_list.html', isFragment: true);
    });

    scopedTest('platform tabs: search', () {
      final String html = renderSdkTabs(
          searchForm: SearchForm.parse(
        query: 'foo',
        sdk: 'flutter',
      ));
      expectGoldenFile(html, 'platform_tabs_search.html', isFragment: true);
    });
  });

  group('PageLinks', () {
    scopedTest('empty', () {
      final links = PageLinks.empty();
      expect(links.currentPage, 1);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 1);
    });

    scopedTest('one', () {
      final links = PageLinks(SearchForm.parse(), 1);
      expect(links.currentPage, 1);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 1);
    });

    scopedTest('PageLinks.RESULTS_PER_PAGE - 1', () {
      final links = PageLinks(SearchForm.parse(), resultsPerPage - 1);
      expect(links.currentPage, 1);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 1);
    });

    scopedTest('PageLinks.RESULTS_PER_PAGE', () {
      final links = PageLinks(SearchForm.parse(), resultsPerPage);
      expect(links.currentPage, 1);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 1);
    });

    scopedTest('PageLinks.RESULTS_PER_PAGE + 1', () {
      final links = PageLinks(SearchForm.parse(), resultsPerPage + 1);
      expect(links.currentPage, 1);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 2);
    });

    final int page2Offset = resultsPerPage;

    scopedTest('page=2 + one item', () {
      final links =
          PageLinks(SearchForm.parse(currentPage: 2), page2Offset + 1);
      expect(links.currentPage, 2);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 2);
    });

    scopedTest('page=2 + PageLinks.RESULTS_PER_PAGE - 1', () {
      final links = PageLinks(
          SearchForm.parse(currentPage: 2), page2Offset + resultsPerPage - 1);
      expect(links.currentPage, 2);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 2);
    });

    scopedTest('page=2 + PageLinks.RESULTS_PER_PAGE', () {
      final links = PageLinks(
          SearchForm.parse(currentPage: 2), page2Offset + resultsPerPage);
      expect(links.currentPage, 2);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 2);
    });

    scopedTest('page=2 + PageLinks.RESULTS_PER_PAGE + 1', () {
      final links = PageLinks(
          SearchForm.parse(currentPage: 2), page2Offset + resultsPerPage + 1);
      expect(links.currentPage, 2);
      expect(links.leftmostPage, 1);
      expect(links.rightmostPage, 3);
    });

    scopedTest('deep in the middle', () {
      final links = PageLinks(SearchForm.parse(currentPage: 21), 600);
      expect(links.currentPage, 21);
      expect(links.leftmostPage, 16);
      expect(links.rightmostPage, 26);
    });
  });
}

final _panaRuntimeInfo = PanaRuntimeInfo(
  panaVersion: '0.6.2',
  flutterVersions: {'frameworkVersion': '0.0.18'},
  sdkVersion: '2.0.0-dev.7.0',
);
