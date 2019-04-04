// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:mime/mime.dart' as mime;
import 'package:pana/pana.dart' show runProc;
import 'package:path/path.dart' as path;

const String _defaultStaticPath = '/static';
const _staticRootPaths = <String>['favicon.ico', 'robots.txt'];

StaticFileCache _cache;

/// The static file cache. If no cache was registered before the first access,
/// the default instance will be created.
StaticFileCache get staticFileCache =>
    _cache ??= StaticFileCache.withDefaults();

/// Register the static file cache.
/// Can be called only once, before the static file cache is set.
void registerStaticFileCache(StaticFileCache cache) {
  assert(_cache == null);
  _cache = cache;
}

/// Returns the path of the `app/` directory.
String resolveAppDir() {
  if (Platform.script.path.contains('bin/server.dart')) {
    return Platform.script.resolve('../').toFilePath();
  }
  if (Platform.script.path.contains('bin/fake_pub_server.dart')) {
    return Platform.script.resolve('../../../app').toFilePath();
  }
  if (Platform.script.path.contains('app/test')) {
    return Directory.current.path;
  }
  throw Exception('Unknown script: ${Platform.script}');
}

String _resolveStaticDirPath() {
  return path.join(resolveAppDir(), '../static');
}

String _resolveWebAppDirPath() {
  return path.join(resolveAppDir(), '../pkg/web_app');
}

String _resolveRootDirPath() =>
    Directory(path.join(resolveAppDir(), '../')).resolveSymbolicLinksSync();
Directory _resolveDir(String relativePath) =>
    Directory(path.join(_resolveRootDirPath(), relativePath)).absolute;

/// Stores static files in memory for fast http serving.
class StaticFileCache {
  final _files = <String, StaticFile>{};

  StaticFileCache();

  StaticFileCache.withDefaults() {
    _addDirectory(Directory(_resolveStaticDirPath()).absolute);
    final thirdPartyDir = _resolveDir('third_party');
    _addDirectory(_resolveDir('third_party/highlight'), baseDir: thirdPartyDir);
    _addDirectory(_resolveDir('third_party/css'), baseDir: thirdPartyDir);
  }

  void _addDirectory(Directory contentDir, {Directory baseDir}) {
    baseDir ??= contentDir;
    contentDir
        .listSync(recursive: true)
        .where((fse) => fse is File)
        .map((file) => file.absolute as File)
        .map(
      (File file) {
        final contentType = mime.lookupMimeType(file.path) ?? 'octet/binary';
        final bytes = file.readAsBytesSync();
        final lastModified = file.lastModifiedSync();
        final relativePath = path.relative(file.path, from: baseDir.path);
        final isRoot = _staticRootPaths.contains(relativePath);
        final prefix = isRoot ? '' : _defaultStaticPath;
        final requestPath = '$prefix/$relativePath';
        final digest = crypto.sha256.convert(bytes);
        final String etag =
            digest.bytes.map((b) => (b & 31).toRadixString(32)).join();
        return StaticFile(requestPath, contentType, bytes, lastModified, etag);
      },
    ).forEach(addFile);
  }

  void addFile(StaticFile file) {
    _files[file.requestPath] = file;
  }

  bool hasFile(String requestPath) => _files.containsKey(requestPath);

  StaticFile getFile(String requestPath) => _files[requestPath];
}

/// Stores the content and metadata of a statically served file.
class StaticFile {
  final String requestPath;
  final String contentType;
  final List<int> bytes;
  final DateTime lastModified;
  final String etag;

  StaticFile(
    this.requestPath,
    this.contentType,
    this.bytes,
    this.lastModified,
    this.etag,
  );
}

final staticUrls = StaticUrls();

class StaticUrls {
  final String staticPath = _defaultStaticPath;
  final String smallDartFavicon;
  final String dartLogoSvg;
  final String flutterLogo32x32;
  final String documentationIcon;
  final String downloadIcon;
  Map _versionsTableIcons;
  Map<String, String> _assets;

  StaticUrls()
      : smallDartFavicon = '/favicon.ico',
        dartLogoSvg = '$_defaultStaticPath/img/dart-logo.svg',
        flutterLogo32x32 = '$_defaultStaticPath/img/flutter-logo-32x32.png',
        documentationIcon =
            '$_defaultStaticPath/img/ic_drive_document_black_24dp.svg',
        downloadIcon = '$_defaultStaticPath/img/ic_get_app_black_24dp.svg';

  Map get versionsTableIcons {
    return _versionsTableIcons ??= {
      'documentation': documentationIcon,
      'download': downloadIcon,
    };
  }

  Map<String, String> get assets {
    return _assets ??= {
      'gtag_js': _getCacheableStaticUrl('/js/gtag.js'),
      'script_dart_js': _getCacheableStaticUrl('/js/script.dart.js'),
      'github_markdown_css': _getCacheableStaticUrl('/css/github-markdown.css'),
      'style_css': _getCacheableStaticUrl('/css/style.css'),
    };
  }

  /// Returns the URL of a static resource
  String _getCacheableStaticUrl(String relativePath) {
    if (!relativePath.startsWith('/')) {
      relativePath = '/$relativePath';
    }
    final String requestPath = '$staticPath$relativePath';
    final file = staticFileCache.getFile(requestPath);
    if (file == null) {
      throw Exception('Static resource not found: $relativePath');
    } else {
      return '$requestPath?hash=${file.etag}';
    }
  }
}

Future updateLocalBuiltFiles() async {
  final staticDir = Directory(_resolveStaticDirPath());
  final webAppDir = Directory(_resolveWebAppDirPath());
  final scriptDart = File(path.join(webAppDir.path, 'lib', 'script.dart'));
  final scriptJs = File(path.join(staticDir.path, 'js', 'script.dart.js'));
  if (!scriptJs.existsSync() ||
      (scriptJs.lastModifiedSync().isBefore(scriptDart.lastModifiedSync()))) {
    await scriptJs.parent.create(recursive: true);
    final pr = await runProc(
      'dart2js',
      [
        '--dump-info',
        '--minify',
        '--trust-primitives',
        '--omit-implicit-checks',
        scriptDart.path,
        '-o',
        scriptJs.path,
      ],
      workingDirectory: staticDir.path,
      timeout: const Duration(minutes: 2),
    );
    if (pr.exitCode != 0) {
      final message = 'Unable to compile script.dart\n\n'
          'exitCode: ${pr.exitCode}\n'
          'STDOUT:\n${pr.stdout}\n\n'
          'STDERR:\n${pr.stderr}';
      throw Exception(message);
    }
  }
}
