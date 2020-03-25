// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_server.shelf_pubserver;

import 'dart:async';
import 'dart:convert' as convert;

import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:shelf/shelf.dart' as shelf;
import 'package:yaml/yaml.dart';

import '../../package/backend.dart' show purgePackageCache;
import '../../shared/exceptions.dart';
import '../../shared/redis_cache.dart' show cache;
import '../../shared/urls.dart' as urls;

import 'repository.dart';

final Logger _logger = Logger('pubserver.shelf_pubserver');

/// It will use the pub [PackageRepository] given in the constructor to provide
/// this HTTP endpoint.
class ShelfPubServer {
  final PackageRepository repository;

  ShelfPubServer(this.repository);

  // Metadata handlers.

  Future<shelf.Response> listVersions(Uri uri, String package) async {
    final cachedBinaryJson = await cache.packageData(package).get();
    if (cachedBinaryJson != null) {
      return _binaryJsonResponse(cachedBinaryJson);
    }

    final packageVersions = await repository.versions(package).toList();
    if (packageVersions.isEmpty) {
      return shelf.Response.notFound(null);
    }

    packageVersions.sort((a, b) => a.version.compareTo(b.version));

    // TODO: Add legacy entries (if necessary), such as version_url.
    Map packageVersion2Json(PackageVersion version) {
      return {
        'archive_url': urls.pkgArchiveDownloadUrl(
            version.packageName, version.versionString,
            baseUri: uri),
        'pubspec': loadYaml(version.pubspecYaml),
        'version': version.versionString,
      };
    }

    var latestVersion = packageVersions.last;
    for (int i = packageVersions.length - 1; i >= 0; i--) {
      if (!packageVersions[i].version.isPreRelease) {
        latestVersion = packageVersions[i];
        break;
      }
    }

    // TODO: The 'latest' is something we should get rid of, since it's
    // duplicated in 'versions'.
    final binaryJson = convert.json.encoder.fuse(convert.utf8.encoder).convert({
      'name': package,
      'latest': packageVersion2Json(latestVersion),
      'versions': packageVersions.map(packageVersion2Json).toList(),
    });
    await cache.packageData(package).set(binaryJson);
    return _binaryJsonResponse(binaryJson);
  }

  Future<shelf.Response> showVersion(
      Uri uri, String package, String version) async {
    InvalidInputException.check(isSemanticVersion(version),
        'Version string "$version" is not a valid semantic version.');

    final ver = await repository.lookupVersion(package, version);
    if (ver == null) {
      return shelf.Response.notFound(null);
    }

    // TODO: Add legacy entries (if necessary), such as version_url.
    return _jsonResponse({
      'archive_url': urls.pkgArchiveDownloadUrl(
          ver.packageName, ver.versionString,
          baseUri: uri),
      'pubspec': loadYaml(ver.pubspecYaml),
      'version': ver.versionString,
    });
  }

  // Download handlers.

  Future<shelf.Response> download(
      Uri uri, String package, String version) async {
    InvalidInputException.check(isSemanticVersion(version),
        'Version string "$version" is not a valid semantic version.');
    final url = await repository.downloadUrl(package, version);
    // This is a redirect to [url]
    return shelf.Response.seeOther(url);
  }

  // Upload async handlers.

  Future<shelf.Response> startUploadAsync(Uri uri) async {
    final info = await repository.startAsyncUpload(_finishUploadAsyncUrl(uri));
    return _jsonResponse({
      'url': '${info.uri}',
      'fields': info.fields,
    });
  }

  Future<shelf.Response> finishUploadAsync(Uri uri) async {
    try {
      final vers = await repository.finishAsyncUpload(uri);
      if (cache != null) {
        _logger.info('Invalidating cache for package ${vers.packageName}.');
        await purgePackageCache(vers.packageName);
      }
      return _jsonResponse({
        'success': {
          'message': 'Successfully uploaded package.',
        },
      });
    } on ResponseException catch (error, stack) {
      _logger.info('A problem occured while finishing upload.', error, stack);
      // [ResponseException] is pass-through, no need to do anything here.
      rethrow;
    } catch (error, stack) {
      _logger.warning('An error occured while finishing upload.', error, stack);
      return _jsonResponse({
        'error': {
          'message': '$error.',
        },
      }, status: 500);
    }
  }

  // Uploader handlers.

  Future<shelf.Response> addUploader(String package, String body) async {
    final parts = body.split('=');
    InvalidInputException.check(
        parts.length == 2 && parts[0] == 'email' && parts[1].isNotEmpty,
        'Invalid request.');

    final user = Uri.decodeQueryComponent(parts[1]);
    await repository.addUploader(package, user);
    return _successfullRequest('Successfully added uploader to package.');
  }

  Future<shelf.Response> removeUploader(
      String package, String userEmail) async {
    await repository.removeUploader(package, userEmail);
    return _successfullRequest('Successfully removed uploader from package.');
  }

  // Helper functions.

  Future<shelf.Response> _successfullRequest(String message) async {
    return shelf.Response(200,
        body: convert.json.encode({
          'success': {'message': message}
        }),
        headers: {'content-type': 'application/json'});
  }

  shelf.Response _binaryJsonResponse(List<int> d, {int status = 200}) =>
      shelf.Response(status,
          body: Stream.fromIterable([d]),
          headers: {'content-type': 'application/json'});

  shelf.Response _jsonResponse(Map json, {int status = 200}) =>
      shelf.Response(status,
          body: convert.json.encode(json),
          headers: {'content-type': 'application/json'});

  // Upload async urls.

  Uri _finishUploadAsyncUrl(Uri url) =>
      url.resolve('/api/packages/versions/newUploadFinish');

  bool isSemanticVersion(String version) {
    try {
      semver.Version.parse(version);
      return true;
    } catch (_) {
      return false;
    }
  }
}
