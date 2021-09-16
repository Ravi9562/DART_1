// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:client_data/page_data.dart';
import 'package:pana/pana.dart' show getRepositoryUrl;

import '../../package/models.dart';
import '../../package/overrides.dart' show devDependencyPackages;
import '../../shared/handlers.dart';
import '../../shared/tags.dart';
import '../../shared/urls.dart' as urls;

import '../dom/dom.dart' as d;
import '../static_files.dart';

import '_utils.dart';
import 'detail_page.dart';
import 'layout.dart';
import 'misc.dart';
import 'package_misc.dart';
import 'views/pkg/header.dart';
import 'views/pkg/info_box.dart';
import 'views/pkg/install_tab.dart';
import 'views/pkg/score_tab.dart';
import 'views/pkg/title_content.dart';

/// Renders the right-side info box (quick summary of the package, mostly coming
/// from pubspec.yaml).
String renderPkgInfoBox(PackagePageData data) {
  final package = data.package!;
  final packageLinks = data.version!.packageLinks;

  String? documentationUrl = packageLinks.documentationUrl;
  if (urls.hideUserProvidedDocUrl(documentationUrl)) {
    documentationUrl = null;
  }
  final dartdocsUrl = urls.pkgDocUrl(
    package.name!,
    version: data.version!.version,
    isLatest: data.isLatestStable,
  );

  final metaLinks = <InfoBoxLink>[];
  final docLinks = <InfoBoxLink>[];
  void addLink(
    String? href,
    String label, {
    bool detectServiceProvider = false,
    bool documentation = false,
  }) {
    final uri = urls.parseValidUrl(href);
    if (uri == null) return;

    if (detectServiceProvider) {
      final providerName = urls.inferServiceProviderName(href);
      if (providerName != null) {
        label += ' ($providerName)';
      }
    }
    final linkData = InfoBoxLink(uri.toString(), label,
        rel: uri.shouldIndicateUgc ? 'ugc' : null);
    if (documentation) {
      docLinks.add(linkData);
    } else {
      metaLinks.add(linkData);
    }
  }

  if (packageLinks.repositoryUrl != packageLinks.homepageUrl) {
    addLink(packageLinks.homepageUrl, 'Homepage');
  }
  addLink(packageLinks.repositoryUrl, 'Repository',
      detectServiceProvider: true);
  addLink(packageLinks.issueTrackerUrl, 'View/report issues');
  addLink(documentationUrl, 'Documentation', documentation: true);
  if (data.scoreCard?.hasApiDocs ?? false) {
    addLink(dartdocsUrl, 'API reference', documentation: true);
  }

  return packageInfoBoxNode(
    data: data,
    metaLinks: metaLinks,
    docLinks: docLinks,
    labeledScores: labeledScoresNodeFromPackageView(
      data.toPackageView(),
      version: data.isLatestStable ? null : data.version!.version,
    ),
  ).toString();
}

/// Renders the package header template for header metadata and
/// wraps it with content-header.
d.Node renderPkgHeader(PackagePageData data) {
  final package = data.package!;
  final showPrereleaseVersion = data.latestReleases!.showPrerelease;
  final showPreviewVersion = data.latestReleases!.showPreview;
  final bool showReleases =
      !data.isLatestStable || showPrereleaseVersion || showPreviewVersion;

  final isNullSafe =
      data.toPackageView().tags.contains(PackageVersionTags.isNullSafe);
  final metadataNode = packageHeaderNode(
    packageName: package.name!,
    publisherId: package.publisherId,
    published: data.version!.created!,
    isNullSafe: isNullSafe,
    releases: showReleases ? data.latestReleases : null,
  );

  final pkgView = data.toPackageView();
  return renderDetailHeader(
    titleNode: titleContentNode(
      package: package.name!,
      version: data.version!.version!,
    ),
    packageLikes: package.likes,
    isLiked: data.isLiked,
    isFlutterFavorite:
        (package.assignedTags ?? []).contains(PackageTags.isFlutterFavorite),
    metadataNode: metadataNode,
    tagsNode: tagsNodeFromPackageView(
      package: pkgView,
      version: data.isLatestStable ? null : data.version!.version,
    ),
    isLoose: true,
  );
}

/// Renders the package detail page.
String renderPkgShowPage(PackagePageData data) {
  return _renderPkgPage(
    data: data,
    tabs: buildPackageTabs(
      data: data,
      readmeTab: _readmeTab(data),
    ),
    pkgPageTab: urls.PkgPageTab.readme,
  );
}

/// Renders the package changelog page.
String renderPkgChangelogPage(PackagePageData data) {
  return _renderPkgPage(
    data: data,
    tabs: buildPackageTabs(
      data: data,
      changelogTab: _changelogTab(data),
    ),
    pkgPageTab: urls.PkgPageTab.changelog,
  );
}

/// Renders the package example page.
String renderPkgExamplePage(PackagePageData data) {
  return _renderPkgPage(
    data: data,
    tabs: buildPackageTabs(
      data: data,
      exampleTab: _exampleTab(data),
    ),
    pkgPageTab: urls.PkgPageTab.example,
  );
}

/// Renders the package install page.
String renderPkgInstallPage(PackagePageData data) {
  return _renderPkgPage(
    data: data,
    tabs: buildPackageTabs(
      data: data,
      installingTab: _installTab(data),
    ),
    pkgPageTab: urls.PkgPageTab.install,
  );
}

/// Renders the package license page.
String renderPkgLicensePage(PackagePageData data) {
  return _renderPkgPage(
    data: data,
    tabs: buildPackageTabs(
      data: data,
      licenseTab: _licenseTab(data),
    ),
    pkgPageTab: urls.PkgPageTab.license,
  );
}

/// Renders the package pubspec page.
String renderPkgPubspecPage(PackagePageData data) {
  return _renderPkgPage(
    data: data,
    tabs: buildPackageTabs(
      data: data,
      pubspecTab: _pubspecTab(data),
    ),
    pkgPageTab: urls.PkgPageTab.pubspec,
  );
}

/// Renders the package score page.
String renderPkgScorePage(PackagePageData data) {
  return _renderPkgPage(
    data: data,
    tabs: buildPackageTabs(
      data: data,
      scoreTab: _scoreTab(data),
    ),
    pkgPageTab: urls.PkgPageTab.score,
  );
}

String _renderPkgPage({
  required PackagePageData data,
  required List<Tab> tabs,
  required urls.PkgPageTab pkgPageTab,
}) {
  final card = data.scoreCard;

  final content = renderDetailPage(
    headerNode: renderPkgHeader(data),
    tabs: tabs,
    infoBoxLead: data.version!.ellipsizedDescription,
    infoBoxNode: renderPkgInfoBox(data),
    footerNode: renderPackageSchemaOrgHtml(data),
  );

  final isFlutterPackage = data.version!.pubspec!.usesFlutter;
  final packageAndVersion = data.isLatestStable
      ? data.package!.name
      : '${data.package!.name} ${data.version!.version}';
  final pageTitle =
      '$packageAndVersion | ${isFlutterPackage ? 'Flutter' : 'Dart'} Package';
  final canonicalUrl = urls.pkgPageUrl(
    data.package!.name!,
    version: data.isLatestStable ? null : data.version!.version,
    includeHost: true,
    pkgPageTab: pkgPageTab,
  );
  final noIndex = (card?.isSkipped ?? false) ||
      (card?.grantedPubPoints == 0) ||
      data.package!.isExcludedInRobots;
  return renderLayoutPage(
    PageType.package,
    content,
    title: pageTitle,
    pageDescription: data.version!.ellipsizedDescription,
    faviconUrl: isFlutterPackage ? staticUrls.flutterLogo32x32 : null,
    canonicalUrl: canonicalUrl,
    noIndex: noIndex,
    pageData: pkgPageData(data.package!, data.version!),
  );
}

PageData pkgPageData(Package package, PackageVersion selectedVersion) {
  return PageData(
    pkgData: PkgData(
        package: package.name!,
        version: selectedVersion.version!,
        publisherId: package.publisherId,
        isDiscontinued: package.isDiscontinued,
        likes: package.likes),
  );
}

Tab _readmeTab(PackagePageData data) {
  final baseUrl = data.version!.packageLinks.baseUrl;
  final content = data.hasReadme &&
          data.asset != null &&
          data.asset!.kind == AssetKind.readme
      ? renderFile(data.asset!.toFileObject(), baseUrl: baseUrl)
      : '';
  return Tab.withContent(
    id: 'readme',
    title: 'Readme',
    contentHtml: content,
    isMarkdown: true,
  );
}

Tab? _changelogTab(PackagePageData data) {
  if (!data.hasChangelog) return null;
  if (data.asset?.kind != AssetKind.changelog) return null;
  final content = renderFile(
    data.asset!.toFileObject(),
    baseUrl: data.version!.packageLinks.baseUrl,
    isChangelog: true,
  );
  return Tab.withContent(
    id: 'changelog',
    title: 'Changelog',
    contentHtml: content,
    isMarkdown: true,
  );
}

Tab? _exampleTab(PackagePageData data) {
  if (!data.hasExample) return null;
  if (data.asset?.kind != AssetKind.example) return null;
  final baseUrl = data.version!.packageLinks.baseUrl;

  final exampleFilename = data.asset!.path;
  var renderedExample =
      renderFile(data.asset!.toFileObject(), baseUrl: baseUrl);
  final url = getRepositoryUrl(baseUrl, exampleFilename!);
  final escapedName = htmlEscape.convert(exampleFilename);
  final link = url == null
      ? escapedName
      : '<a href="$url" target="_blank" rel="noopener noreferrer nofollow">$escapedName</a>';
  renderedExample = '<p style="font-family: monospace"><b>$link</b></p>\n'
      '$renderedExample';

  return Tab.withContent(
    id: 'example',
    title: 'Example',
    contentHtml: renderedExample,
    isMarkdown: true,
  );
}

Tab _installTab(PackagePageData data) {
  final content = installTabNode(
    version: data.version!,
    tags: data.scoreCard?.panaReport?.derivedTags,
    isDevDependency: devDependencyPackages.contains(data.version!.package),
  ).toString();

  return Tab.withContent(
    id: 'installing',
    title: 'Installing',
    contentHtml: content,
    isMarkdown: true,
  );
}

Tab _licenseTab(PackagePageData data) {
  final licenseAsHtml = data.hasLicense
      ? renderFile(
          data.asset!.toFileObject(),
          baseUrl: data.version!.packageLinks.baseUrl,
        )
      : 'No license file found.';
  final contentHtml = '<h2>License</h2>\n$licenseAsHtml';
  return Tab.withContent(
    id: 'license',
    title: 'License',
    contentHtml: contentHtml,
    isMarkdown: true,
  );
}

Tab _pubspecTab(PackagePageData data) {
  final contentHtml = data.hasPubspec
      ? renderFile(
          data.asset!.toFileObject(),
          baseUrl: data.version!.packageLinks.baseUrl,
        )
      : 'No license file found.';
  return Tab.withContent(
    id: 'pubspec',
    title: 'Pubspec',
    contentHtml: contentHtml,
  );
}

Tab _scoreTab(PackagePageData data) {
  return Tab.withContent(
    id: 'analysis',
    title: 'Scores',
    contentHtml: scoreTabNode(
      card: data.scoreCard,
      likeCount: data.package!.likes,
    ).toString(),
  );
}

d.Node renderPackageSchemaOrgHtml(PackagePageData data) {
  final p = data.package!;
  final pv = data.version!;
  final map = <String, dynamic>{
    '@context': 'http://schema.org',
    '@type': 'SoftwareSourceCode',
    'name': p.name,
    'version': pv.version,
    'description': '${p.name} - ${pv.pubspec!.description}',
    'url': urls.pkgPageUrl(p.name!, includeHost: true),
    'dateCreated': p.created!.toIso8601String(),
    'dateModified': pv.created!.toIso8601String(),
    'programmingLanguage': 'Dart',
    'image':
        '${urls.siteRoot}${staticUrls.staticPath}/img/pub-dev-icon-cover-image.png'
  };
  final licenseFileUrl = data.scoreCard?.panaReport?.licenseFile?.url;
  if (licenseFileUrl != null) {
    map['license'] = licenseFileUrl;
  }
  // TODO: add http://schema.org/codeRepository for github and gitlab links
  return d.ldJson(map);
}

/// Build package tabs.
///
/// Unspecified tab content will be filled with links to the corresponding page.
List<Tab> buildPackageTabs({
  required PackagePageData data,
  Tab? readmeTab,
  Tab? changelogTab,
  Tab? exampleTab,
  Tab? installingTab,
  Tab? licenseTab,
  Tab? pubspecTab,
  Tab? versionsTab,
  Tab? scoreTab,
  Tab? adminTab,
  Tab? activityLogTab,
}) {
  final package = data.package!;
  final linkVersion = data.isLatestStable ? null : data.version!.version;
  readmeTab ??= Tab.withLink(
    id: 'readme',
    title: 'Readme',
    href: urls.pkgReadmeUrl(package.name!, version: linkVersion),
  );
  changelogTab ??= Tab.withLink(
    id: 'changelog',
    title: 'Changelog',
    href: urls.pkgChangelogUrl(package.name!, version: linkVersion),
  );
  exampleTab ??= Tab.withLink(
    id: 'example',
    title: 'Example',
    href: urls.pkgExampleUrl(package.name!, version: linkVersion),
  );
  installingTab ??= Tab.withLink(
    id: 'installing',
    title: 'Installing',
    href: urls.pkgInstallUrl(package.name!, version: linkVersion),
  );
  versionsTab ??= Tab.withLink(
    id: 'versions',
    title: 'Versions',
    href: urls.pkgVersionsUrl(package.name!),
  );
  scoreTab ??= Tab.withLink(
    id: 'analysis',
    title: 'Scores',
    href: urls.pkgScoreUrl(package.name!, version: linkVersion),
  );
  adminTab ??= Tab.withLink(
    id: 'admin',
    title: 'Admin',
    href: urls.pkgAdminUrl(package.name!),
  );
  activityLogTab ??= Tab.withLink(
    id: 'activity-log',
    title: 'Activity log',
    href: urls.pkgActivityLogUrl(package.name!),
  );
  return <Tab>[
    readmeTab,
    if (data.hasChangelog) changelogTab,
    if (data.hasExample) exampleTab,
    installingTab,
    if (licenseTab != null) licenseTab,
    if (pubspecTab != null) pubspecTab,
    versionsTab,
    scoreTab,
    if (data.isAdmin!) adminTab,
    if (data.isAdmin!) activityLogTab,
  ];
}

/// Renders the package page when the package has been moderated.
String renderModeratedPackagePage(String packageName) {
  final message = 'The package `$packageName` has been removed.';
  return renderErrorPage(default404NotFound, message);
}
