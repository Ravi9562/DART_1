// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_dartlang_org.handlers;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart' as mime;
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;

import '../shared/handlers.dart';

import 'atom_feed.dart';
import 'backend.dart';
import 'handlers_redirects.dart';
import 'models.dart';
import 'search_service.dart';
import 'templates.dart';

final String StaticsLocation =
    Platform.script.resolve('../../static').toFilePath();

/// Handler for the whole URL space of pub.dartlang.org
///
/// The passed in [shelfPubApi] handler will be used for handling requests to
///   - /api/*
Future<shelf.Response> appHandler(
    shelf.Request request, shelf.Handler shelfPubApi) async {
  final path = request.requestedUri.path;

  logPubHeaders(request);

  final handler = {
    '/': indexHandler,
    '/feed.atom': atomFeedHandler,
    '/authorized': authorizedHandler,
    '/search': searchHandler,
    '/packages': packagesHandler,
    '/packages.json': packagesHandler,
    '/flutter': flutterHandler,
    '/flutter/': flutterHandler,
    '/flutter/plugins': flutterPluginsHandler,
  }[path];

  if (handler != null) {
    return handler(request);
  } else if (path == '/api/packages') {
    // NOTE: This is special-cased, since it is not an API used by pub but
    // rather by the editor.
    return apiPackagesHandler(request);
  } else if (path.startsWith('/api') ||
      path.startsWith('/packages') && path.endsWith('.tar.gz')) {
    return shelfPubApi(request);
  } else if (path.startsWith('/packages/')) {
    return packageHandler(request);
  } else if (path.startsWith('/doc')) {
    return docHandler(request);
  } else if (path.startsWith('/static')) {
    return staticsHandler(request);
  } else {
    return _formattedNotFoundHandler(request);
  }
}

/// Handles requests for /
Future<shelf.Response> indexHandler(_) async {
  String pageContent = await backend.uiPackageCache?.getUIIndexPage();
  if (pageContent == null) {
    final versions = await backend.latestPackageVersions(limit: 5);
    assert(!versions.any((version) => version == null));
    pageContent = templateService.renderIndexPage(versions);
    await backend.uiPackageCache?.setUIIndexPage(pageContent);
  }
  return htmlResponse(pageContent);
}

/// Handles requests for /feed.atom
Future<shelf.Response> atomFeedHandler(shelf.Request request) async {
  final int PageSize = 10;

  // The python version had paging support, but there was no point to it, since
  // the "next page" link was never returned to the caller.
  final int page = 1;

  final versions = await backend.latestPackageVersions(
      offset: PageSize * (page - 1), limit: PageSize);
  final feed = feedFromPackageVersions(request.requestedUri, versions);
  return atomXmlResponse(feed.toXmlDocument());
}

/// Handles requests for /authorized
shelf.Response authorizedHandler(_) =>
    htmlResponse(templateService.renderAuthorizedPage());

/// Handles requests for /doc
shelf.Response docHandler(shelf.Request request) {
  final pubDocUrl = 'https://www.dartlang.org/tools/pub/';
  final dartlangDotOrgPath = REDIRECT_PATHS[request.requestedUri.path];
  if (dartlangDotOrgPath != null) {
    return redirectResponse('$pubDocUrl$dartlangDotOrgPath');
  }
  return redirectResponse(pubDocUrl);
}

/// Handles requests for /search
Future<shelf.Response> searchHandler(shelf.Request request) async {
  final queryText = request.url.queryParameters['q'];
  final int page = _pageFromUrl(request.url,
      maxPages: SEARCH_MAX_RESULTS ~/ PageLinks.RESULTS_PER_PAGE);
  final SearchBias expBias =
      parseExperimentalBias(request.url.queryParameters['experimental-bias']);

  final SearchQuery query = new SearchQuery(
    queryText,
    offset: PageLinks.RESULTS_PER_PAGE * (page - 1),
    limit: PageLinks.RESULTS_PER_PAGE,
    type: request.url.queryParameters['type'],
    bias: expBias,
  );
  if (!query.isValid) {
    return htmlResponse(templateService.renderSearchPage(
        new SearchResultPage.empty(query), new SearchLinks.empty(query)));
  }

  final resultPage = await searchService.search(query);
  final links = new SearchLinks(query, resultPage.totalCount);
  return htmlResponse(templateService.renderSearchPage(resultPage, links));
}

/// Handles requests for /packages - multiplexes to JSON/HTML handler.
Future<shelf.Response> packagesHandler(shelf.Request request) async {
  final int page = _pageFromUrl(request.url);
  final path = request.requestedUri.path;
  if (path.endsWith('.json')) {
    return packagesHandlerJson(request, page, true);
  } else if (request.url.queryParameters['format'] == 'json') {
    return packagesHandlerJson(request, page, false);
  } else {
    return packagesHandlerHtml(request, page);
  }
}

/// Handles requests for /static
final StaticsCache staticsCache = new StaticsCache();

Future<shelf.Response> staticsHandler(shelf.Request request) async {
  // Simplifies all of '.', '..', '//'!
  final String normalized = path.normalize(request.requestedUri.path);
  if (normalized.startsWith('/static/')) {
    final assetPath =
        '$StaticsLocation/${normalized.substring('/static/'.length)}';

    final StaticFile staticFile = staticsCache.staticFiles[assetPath];
    if (staticFile != null) {
      return new shelf.Response.ok(staticFile.bytes,
          headers: {'content-type': staticFile.contentType});
    }
  }
  return _formattedNotFoundHandler(request);
}

/// Handles requests for /packages - JSON
Future<shelf.Response> packagesHandlerJson(
    shelf.Request request, int page, bool dotJsonResponse) async {
  final PageSize = 50;

  final offset = PageSize * (page - 1);
  final limit = PageSize + 1;

  final packages = await backend.latestPackages(offset: offset, limit: limit);
  final bool lastPage = packages.length < limit;

  var nextPageUrl;
  if (!lastPage) {
    nextPageUrl =
        request.requestedUri.resolve('/packages.json?page=${page + 1}');
  }

  String toUrl(Package package) {
    final postfix = dotJsonResponse ? '.json' : '';
    return request.requestedUri
        .resolve('/packages/${Uri.encodeComponent(package.name)}$postfix')
        .toString();
  }

  final json = {
    'packages': packages.take(PageSize).map(toUrl).toList(),
    'next': nextPageUrl != null ? '$nextPageUrl' : null,

    // NOTE: We're not returning the following entry:
    //   - 'prev'
    //   - 'pages'
  };

  return jsonResponse(json);
}

/// Handles requests for `/packages` (default behavior) or `/flutter/plugins`
/// (when [basePath] is specified) - HTML
Future<shelf.Response> packagesHandlerHtml(
  shelf.Request request,
  int page, {
  String basePath,
  String detectedType,
  String title,
  String faviconUrl,
  String descriptionHtml,
}) async {
  final offset = PackageLinks.RESULTS_PER_PAGE * (page - 1);
  final limit = PackageLinks.MAX_PAGES * PackageLinks.RESULTS_PER_PAGE + 1;

  final packages = await backend.latestPackages(
      offset: offset, limit: limit, detectedType: detectedType);
  final links =
      new PackageLinks(offset, offset + packages.length, basePath: basePath);
  final pagePackages = packages.take(PackageLinks.RESULTS_PER_PAGE).toList();
  final versions = await backend.lookupLatestVersions(pagePackages);
  return htmlResponse(templateService.renderPkgIndexPage(
    pagePackages,
    versions,
    links,
    title: title,
    faviconUrl: faviconUrl,
    descriptionHtml: descriptionHtml,
  ));
}

/// Handles requests for /packages/...  - multiplexes to HTML/JSON handlers
///
/// Handles the following URLs:
///   - /packages/<package>
///   - /packages/<package>/versions
FutureOr<shelf.Response> packageHandler(shelf.Request request) {
  var path = request.requestedUri.path.substring('/packages/'.length);
  if (path.length == 0) {
    return _formattedNotFoundHandler(request);
  }

  final int slash = path.indexOf('/');
  if (slash == -1) {
    bool responseAsJson = request.url.queryParameters['format'] == 'json';
    if (path.endsWith('.json')) {
      responseAsJson = true;
      path = path.substring(0, path.length - '.json'.length);
    }
    if (responseAsJson) {
      return packageShowHandlerJson(request, Uri.decodeComponent(path));
    } else {
      return packageShowHandlerHtml(request, Uri.decodeComponent(path));
    }
  }

  final package = Uri.decodeComponent(path.substring(0, slash));
  if (path.substring(slash).startsWith('/versions')) {
    path = path.substring(slash + '/versions'.length);
    if (path.startsWith('/')) {
      if (path.endsWith('.yaml')) {
        path = path.substring(1, path.length - '.yaml'.length);
        final String version = Uri.decodeComponent(path);
        return packageVersionHandlerYaml(request, package, version);
      } else {
        path = path.substring(1);
        final String version = Uri.decodeComponent(path);
        return packageVersionHandlerHtml(request, package, version);
      }
    } else {
      return packageVersionsHandler(request, package);
    }
  }
  return _formattedNotFoundHandler(request);
}

/// Handles requests for /packages/<package> - JSON
Future<shelf.Response> packageShowHandlerJson(
    shelf.Request request, String packageName) async {
  final Package package = await backend.lookupPackage(packageName);
  if (package == null) return _formattedNotFoundHandler(request);

  final versions = await backend.versionsOfPackage(packageName);
  sortPackageVersionsDesc(versions, decreasing: false);

  final json = {
    'name': package.name,
    'uploaders': package.uploaderEmails,
    'versions':
        versions.map((packageVersion) => packageVersion.version).toList(),
  };
  return jsonResponse(json);
}

/// Handles requests for /packages/<package> - HTML
Future<shelf.Response> packageShowHandlerHtml(
    shelf.Request request, String packageName) async {
  return packageVersionHandlerHtml(request, packageName, null);
}

/// Handles requests for /packages/<package>/versions
Future<shelf.Response> packageVersionsHandler(
    shelf.Request request, String packageName) async {
  final versions = await backend.versionsOfPackage(packageName);
  if (versions.isEmpty) return _formattedNotFoundHandler(request);

  sortPackageVersionsDesc(versions);

  final versionDownloadUrls =
      await Future.wait(versions.map((PackageVersion version) {
    return backend.downloadUrl(packageName, version.version);
  }).toList());

  return htmlResponse(templateService.renderPkgVersionsPage(
      packageName, versions, versionDownloadUrls));
}

/// Handles requests for /packages/<package>/versions/<version>
Future<shelf.Response> packageVersionHandlerHtml(
    request, String packageName, String versionName) async {
  String cachedPage;
  if (backend.uiPackageCache != null) {
    cachedPage =
        await backend.uiPackageCache.getUIPackagePage(packageName, versionName);
  }

  if (cachedPage == null) {
    final Package package = await backend.lookupPackage(packageName);
    if (package == null) return _formattedNotFoundHandler(request);

    final versions = await backend.versionsOfPackage(packageName);

    sortPackageVersionsDesc(versions, decreasing: true, pubSorting: true);
    final latestStable = versions[0];
    final first10Versions = versions.take(10).toList();

    sortPackageVersionsDesc(versions, decreasing: true, pubSorting: false);
    final latestDev = versions[0];

    var selectedVersion;
    if (versionName != null) {
      for (var v in versions) {
        if (v.version == versionName) selectedVersion = v;
      }
      // TODO: cache error?
      if (selectedVersion == null) {
        return _formattedNotFoundHandler(request);
      }
    } else {
      if (selectedVersion == null) {
        selectedVersion = latestStable;
      }
    }

    final versionDownloadUrls =
        await Future.wait(first10Versions.map((PackageVersion version) {
      return backend.downloadUrl(packageName, version.version);
    }).toList());

    cachedPage = templateService.renderPkgShowPage(
        package,
        first10Versions,
        versionDownloadUrls,
        selectedVersion,
        latestStable,
        latestDev,
        versions.length);
    if (backend.uiPackageCache != null) {
      await backend.uiPackageCache
          .setUIPackagePage(packageName, versionName, cachedPage);
    }
  }

  return htmlResponse(cachedPage);
}

/// Handles requests for /packages/<package>/versions/<version>.yaml
Future<shelf.Response> packageVersionHandlerYaml(
    request, String package, String version) async {
  final packageVersion = await backend.lookupPackageVersion(package, version);
  if (packageVersion == null) {
    return _formattedNotFoundHandler(request);
  } else {
    return yamlResponse(packageVersion.pubspec.jsonString);
  }
}

/// Handles request for /api/packages?page=<num>
Future<shelf.Response> apiPackagesHandler(shelf.Request request) async {
  final int PageSize = 100;

  final int page = _pageFromUrl(request.url);

  final packages = await backend.latestPackages(
      offset: PageSize * (page - 1), limit: PageSize + 1);

  // NOTE: We queried for `PageSize+1` packages, if we get less than that, we
  // know it was the last page.
  // But we only use `PageSize` packages to display in the result.
  final List<Package> pagePackages = packages.take(PageSize).toList();
  final List<PackageVersion> pageVersions =
      await backend.lookupLatestVersions(pagePackages);

  final lastPage = packages.length == pagePackages.length;

  final packagesJson = [];

  final uri = request.requestedUri;
  for (var version in pageVersions) {
    final versionString = Uri.encodeComponent(version.version);
    final packageString = Uri.encodeComponent(version.package);

    final apiArchiveUrl = uri
        .resolve('/packages/$packageString/versions/$versionString.tar.gz')
        .toString();
    final apiPackageUrl =
        uri.resolve('/api/packages/$packageString').toString();
    final apiPackageVersionUrl = uri
        .resolve('/api/packages/$packageString/versions/$versionString')
        .toString();
    final apiNewPackageVersionUrl =
        uri.resolve('/api/packages/$packageString/new').toString();
    final apiUploadersUrl =
        uri.resolve('/api/packages/$packageString/uploaders').toString();
    final versionUrl = uri
        .resolve('/api/packages/$packageString/versions/{version}')
        .toString();

    packagesJson.add({
      'name': version.package,
      'latest': {
        'version': version.version,
        'pubspec': version.pubspec.asJson,

        // TODO: We should get rid of these:
        'archive_url': apiArchiveUrl,
        'package_url': apiPackageUrl,
        'url': apiPackageVersionUrl,

        // NOTE: We do not add the following
        //    - 'new_dartdoc_url'
      },
      // TODO: We should get rid of these:
      'url': apiPackageUrl,
      'version_url': versionUrl,
      'new_version_url': apiNewPackageVersionUrl,
      'uploaders_url': apiUploadersUrl,
    });
  }

  final Map<String, dynamic> json = {
    'next_url': null,
    'packages': packagesJson,

    // NOTE: We do not add the following:
    //     - 'pages'
    //     - 'prev_url'
  };

  if (!lastPage) {
    json['next_url'] =
        '${request.requestedUri.resolve('/api/packages?page=${page + 1}')}';
  }

  return jsonResponse(json);
}

/// Handles requests for /flutter (redirects to /flutter/plugins).
shelf.Response flutterHandler(shelf.Request request) =>
    redirectResponse('/flutter/plugins');

/// Handles requests for /flutter/plugins
Future<shelf.Response> flutterPluginsHandler(shelf.Request request) async {
  final int page = _pageFromUrl(request.url);
  return packagesHandlerHtml(
    request,
    page,
    basePath: '/flutter/plugins',
    detectedType: BuiltinTypes.flutterPlugin,
    title: 'Flutter Plugins',
    faviconUrl: LogoUrls.flutterLogo32x32,
    descriptionHtml: flutterPluginsDescriptionHtml,
  );
}

shelf.Response _formattedNotFoundHandler(request) {
  final message = 'The path \'${request.requestedUri.path}\' was not found.';
  return htmlResponse(
    templateService.renderErrorPage(default404NotFound, message, null),
    status: 404,
  );
}

/// Extracts the 'page' query parameter from [url].
///
/// Returns a valid positive integer. If [maxPages] is given, the result is
/// clamped to [maxPages].
int _pageFromUrl(Uri url, {int maxPages}) {
  final pageAsString = url.queryParameters['page'];
  int pageAsInt = 1;
  if (pageAsString != null) {
    try {
      pageAsInt = max(int.parse(pageAsString), 1);
    } catch (_, __) {}
  }

  if (maxPages != null && pageAsInt > maxPages) pageAsInt = maxPages;
  return pageAsInt;
}

class StaticsCache {
  final Map<String, StaticFile> staticFiles = <String, StaticFile>{};

  StaticsCache() {
    final Directory staticsDirectory = new Directory(StaticsLocation);
    final files = staticsDirectory
        .listSync(recursive: true)
        .where((fse) => fse is File)
        .map((file) => file.absolute);

    for (final File file in files) {
      final contentType = mime.lookupMimeType(file.path) ?? 'octet/binary';
      final bytes = file.readAsBytesSync();
      staticFiles[file.path] = new StaticFile(contentType, bytes);
    }
  }
}

class StaticFile {
  final String contentType;
  final List<int> bytes;

  StaticFile(this.contentType, this.bytes);
}
