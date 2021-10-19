// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:neat_cache/neat_cache.dart';
import 'package:shelf/shelf.dart' as shelf;

import '../../account/backend.dart';
import '../../audit/backend.dart';
import '../../package/backend.dart';
import '../../package/models.dart';
import '../../package/overrides.dart';
import '../../publisher/backend.dart';
import '../../scorecard/backend.dart';
import '../../shared/handlers.dart';
import '../../shared/redis_cache.dart' show cache;
import '../../shared/urls.dart' as urls;
import '../../shared/utils.dart';
import '../../tool/utils/dart_sdk_version.dart';

import '../request_context.dart';
import '../templates/misc.dart';
import '../templates/package.dart';
import '../templates/package_admin.dart';
import '../templates/package_versions.dart';

import 'misc.dart' show formattedNotFoundHandler;

// Non-revealing metrics to monitor the search service behavior from outside.
final _packageDataLoadLatencyTracker = DurationTracker();
final _packageDoneLatencyTracker = DurationTracker();

Map packageDebugStats() {
  return {
    'data_load_latency': _packageDataLoadLatencyTracker.toShortStat(),
    'done_latency': _packageDoneLatencyTracker.toShortStat(),
  };
}

/// Handles requests for /packages/<package> - JSON
Future<shelf.Response> packageShowHandlerJson(
    shelf.Request request, String packageName) async {
  checkPackageVersionParams(packageName);
  final package = await packageBackend.lookupPackage(packageName);
  if (package == null || package.isNotVisible) {
    return formattedNotFoundHandler(request);
  }

  final versions = await packageBackend.versionsOfPackage(packageName);
  sortPackageVersionsDesc(versions, decreasing: false);

  final json = {
    'name': package.name,
    'versions':
        versions.map((packageVersion) => packageVersion.version).toList(),
  };
  return jsonResponse(json);
}

/// Handles requests for /packages/<package>/versions
Future<shelf.Response> packageVersionsListHandler(
    shelf.Request request, String packageName) async {
  return _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: null,
    assetKind: null,
    renderFn: (data) async {
      final versions = await packageBackend.versionsOfPackage(packageName);
      if (versions.isEmpty) {
        return redirectToSearch(packageName);
      }

      sortPackageVersionsDesc(versions);
      final dartSdkVersion = await getDartSdkVersion();
      return renderPkgVersionsPage(
        data,
        versions.map((v) => v.toApiVersionInfo()).toList(),
        dartSdkVersion: dartSdkVersion.semanticVersion,
      );
    },
    cacheEntry: cache.uiPackageVersions(packageName),
  );
}

/// Handles requests for /packages/<package>/changelog
/// Handles requests for /packages/<package>/versions/<version>/changelog
Future<shelf.Response> packageChangelogHandler(
    shelf.Request request, String packageName,
    {String? versionName}) async {
  return await _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: versionName,
    assetKind: AssetKind.changelog,
    renderFn: (data) {
      if (!data.hasChangelog) {
        return redirectResponse(
            urls.pkgPageUrl(packageName, version: versionName));
      }
      return renderPkgChangelogPage(data);
    },
    cacheEntry: cache.uiPackageChangelog(packageName, versionName),
  );
}

/// Handles requests for /packages/<package>/example
/// Handles requests for /packages/<package>/versions/<version>/example
Future<shelf.Response> packageExampleHandler(
    shelf.Request request, String packageName,
    {String? versionName}) async {
  return await _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: versionName,
    assetKind: AssetKind.example,
    renderFn: (data) {
      if (!data.hasExample) {
        return redirectResponse(
            urls.pkgPageUrl(packageName, version: versionName));
      }
      return renderPkgExamplePage(data);
    },
    cacheEntry: cache.uiPackageExample(packageName, versionName),
  );
}

/// Handles requests for /packages/<package>/install
/// Handles requests for /packages/<package>/versions/<version>/install
Future<shelf.Response> packageInstallHandler(
    shelf.Request request, String packageName,
    {String? versionName}) async {
  return await _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: versionName,
    assetKind: null,
    renderFn: (data) => renderPkgInstallPage(data),
    cacheEntry: cache.uiPackageInstall(packageName, versionName),
  );
}

/// Handles requests for /packages/<package>/license
/// Handles requests for /packages/<package>/versions/<version>/license
Future<shelf.Response> packageLicenseHandler(
    shelf.Request request, String packageName,
    {String? versionName}) async {
  return await _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: versionName,
    assetKind: AssetKind.license,
    renderFn: (data) => renderPkgLicensePage(data),
    cacheEntry: cache.uiPackageLicense(packageName, versionName),
  );
}

/// Handles requests for /packages/<package>/pubspec
/// Handles requests for /packages/<package>/versions/<version>/pubspec
Future<shelf.Response> packagePubspecHandler(
    shelf.Request request, String packageName,
    {String? versionName}) async {
  return await _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: versionName,
    assetKind: AssetKind.pubspec,
    renderFn: (data) => renderPkgPubspecPage(data),
    cacheEntry: cache.uiPackagePubspec(packageName, versionName),
  );
}

/// Handles requests for /packages/<package>/score
/// Handles requests for /packages/<package>/versions/<version>/score
Future<shelf.Response> packageScoreHandler(
    shelf.Request request, String packageName,
    {String? versionName}) async {
  return await _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: versionName,
    assetKind: null,
    renderFn: (data) => renderPkgScorePage(data),
    cacheEntry: cache.uiPackageScore(packageName, versionName),
  );
}

/// Handles requests for /packages/<package>
/// Handles requests for /packages/<package>/versions/<version>
Future<shelf.Response> packageVersionHandlerHtml(
    shelf.Request request, String packageName,
    {String? versionName}) async {
  return await _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: versionName,
    assetKind: AssetKind.readme,
    renderFn: (data) => renderPkgShowPage(data),
    cacheEntry: cache.uiPackagePage(packageName, versionName),
  );
}

Future<shelf.Response> _handlePackagePage({
  required shelf.Request request,
  required String packageName,
  required String? versionName,
  required String? assetKind,
  required FutureOr Function(PackagePageData data) renderFn,
  Entry<String>? cacheEntry,
}) async {
  checkPackageVersionParams(packageName, versionName);
  if (redirectPackageUrls.containsKey(packageName)) {
    return redirectResponse(redirectPackageUrls[packageName]!);
  }
  final Stopwatch sw = Stopwatch()..start();
  String? cachedPage;
  if (requestContext.uiCacheEnabled && cacheEntry != null) {
    cachedPage = await cacheEntry.get();
  }

  if (cachedPage == null) {
    final serviceSw = Stopwatch()..start();
    final data = await loadPackagePageData(packageName, versionName, assetKind);
    _packageDataLoadLatencyTracker.add(serviceSw.elapsed);
    if (data.package == null ||
        data.package!.isNotVisible ||
        data.version == null) {
      if (data.moderatedPackage != null) {
        final content = renderModeratedPackagePage(packageName);
        return htmlResponse(content, status: 404);
      }
      return formattedNotFoundHandler(request);
    }
    final renderedResult = await renderFn(data);
    if (renderedResult is String) {
      cachedPage = renderedResult;
    } else if (renderedResult is shelf.Response) {
      return renderedResult;
    } else {
      throw StateError('Unknown result type: ${renderedResult.runtimeType}');
    }
    if (requestContext.uiCacheEnabled && cacheEntry != null) {
      await cacheEntry.set(cachedPage);
    }
    _packageDoneLatencyTracker.add(sw.elapsed);
  }
  return htmlResponse(cachedPage);
}

/// Handles requests for /packages/<package>/admin
/// Handles requests for /packages/<package>/versions/<version>/admin
Future<shelf.Response> packageAdminHandler(
    shelf.Request request, String packageName) async {
  return _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: null,
    assetKind: null,
    renderFn: (data) async {
      if (userSessionData == null) {
        return htmlResponse(renderUnauthenticatedPage());
      }
      if (!data.isAdmin!) {
        return htmlResponse(renderUnauthorizedPage());
      }
      final page = await publisherBackend
          .listPublishersForUser(userSessionData!.userId!);
      final uploaderEmails = await accountBackend
          .lookupUsersById(data.package!.uploaders ?? <String>[]);
      return renderPkgAdminPage(
        data,
        page.publishers!.map((p) => p.publisherId).toList(),
        uploaderEmails.cast(),
      );
    },
  );
}

/// Handles requests for /packages/<package>/activity-log
Future<shelf.Response> packageActivityLogHandler(
    shelf.Request request, String packageName) async {
  return _handlePackagePage(
    request: request,
    packageName: packageName,
    versionName: null,
    assetKind: null,
    renderFn: (data) async {
      if (userSessionData == null) {
        return htmlResponse(renderUnauthenticatedPage());
      }
      if (!data.isAdmin!) {
        return htmlResponse(renderUnauthorizedPage());
      }
      final before = auditBackend.parseBeforeQueryParameter(
          request.requestedUri.queryParameters['before']);
      final activities = await auditBackend.listRecordsForPackage(
        packageName,
        before: before,
      );
      return renderPkgActivityLogPage(data, activities);
    },
  );
}

@visibleForTesting
Future<PackagePageData> loadPackagePageData(
  String packageName,
  String? versionName,
  String? assetKind,
) async {
  final package = await packageBackend.lookupPackage(packageName);
  if (package == null || package.isNotVisible) {
    final moderated = await packageBackend.lookupModeratedPackage(packageName);
    return PackagePageData.missing(
      package: null,
      latestReleases: null,
      moderatedPackage: moderated,
    );
  }

  final bool isLiked = (userSessionData == null)
      ? false
      : await accountBackend.getPackageLikeStatus(
              userSessionData!.userId!, package.name!) !=
          null;

  versionName ??= package.latestVersion;
  final selectedVersion =
      await packageBackend.lookupPackageVersion(packageName, versionName!);
  if (selectedVersion == null) {
    return PackagePageData.missing(
      package: package,
      latestReleases: await packageBackend.latestReleases(package),
    );
  }

  final versionInfo =
      await packageBackend.lookupPackageVersionInfo(packageName, versionName);
  if (versionInfo == null) {
    return PackagePageData.missing(
      package: package,
      latestReleases: await packageBackend.latestReleases(package),
    );
  }

  final asset = assetKind == null
      ? null
      : await packageBackend.lookupPackageVersionAsset(
          packageName, versionName, assetKind);

  final scoreCard = await scoreCardBackend.getScoreCardData(
      selectedVersion.package, selectedVersion.version!);

  final isAdmin =
      await packageBackend.isPackageAdmin(package, userSessionData?.userId);

  return PackagePageData(
    package: package,
    latestReleases: await packageBackend.latestReleases(package),
    version: selectedVersion,
    versionInfo: versionInfo,
    asset: asset,
    scoreCard: scoreCard,
    isAdmin: isAdmin,
    isLiked: isLiked,
  );
}

/// Handles /api/packages/<package> requests.
Future<shelf.Response> listVersionsHandler(
    shelf.Request request, String package) async {
  checkPackageVersionParams(package);

  Future<List<int>> createGzipBytes() async {
    final data = await packageBackend.listVersions(package);
    final raw = jsonUtf8Encoder.convert(data.toJson());
    return gzip.encode(raw);
  }

  shelf.Response createResponse(List<int> body, {required bool isGzip}) {
    return shelf.Response(
      200,
      body: body,
      headers: {
        if (isGzip) 'content-encoding': 'gzip',
        'content-type': 'application/json; charset="utf-8"',
        'x-content-type-options': 'nosniff',
      },
    );
  }

  final body = (await cache.packageDataGz(package).get(createGzipBytes))!;
  if (request.acceptsEncoding('gzip')) {
    return createResponse(body!, isGzip: true);
  } else {
    return createResponse(gzip.decode(body!), isGzip: false);
  }
}
