// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:_pub_shared/validation/html/html_validation.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

/// Creates and tracks the headless Chrome environment, its temp directories and
/// and uncaught exceptions.
class HeadlessEnv {
  final String? _testName;
  final String _origin;
  final String? _coverageDir;
  final Directory _tempDir;
  final bool _displayBrowser;
  Browser? _browser;
  final _clientErrors = <ClientError>[];
  final _serverErrors = <String>[];
  late final _trackCoverage =
      _coverageDir != null || Platform.environment.containsKey('COVERAGE');
  final _trackedPages = <Page>[];

  /// The coverage report of JavaScript files.
  final _jsCoverages = <String, _Coverage>{};

  /// The coverage report of CSS files.
  final _cssCoverages = <String, _Coverage>{};

  HeadlessEnv({
    required String origin,
    String? testName,
    String? coverageDir,
    bool displayBrowser = false,
  })  : _displayBrowser = displayBrowser,
        _testName = testName,
        _origin = origin,
        _coverageDir = coverageDir ?? Platform.environment['COVERAGE_DIR'],
        _tempDir = Directory.systemTemp.createTempSync('pub-headless');

  Future<String> _detectChromeBinary() async {
    // TODO: scan $PATH
    // check hardcoded values
    final binaries = [
      '/usr/bin/google-chrome',
    ];
    for (String binary in binaries) {
      if (File(binary).existsSync()) return binary;
    }

    // sanity check for CI
    if (Platform.environment['CI'] == 'true') {
      throw StateError('Could not detect chrome binary while running in CI.');
    }

    // Otherwise let puppeteer download a chrome in the local .dart_tool directory:
    final r = await downloadChrome(cachePath: '.dart_tool/puppeteer/chromium');
    return r.executablePath;
  }

  Future<void> startBrowser() async {
    if (_browser != null) return;
    final chromeBin = await _detectChromeBinary();
    final userDataDir = await _tempDir.createTemp('user');
    _browser = await puppeteer.launch(
      executablePath: chromeBin,
      args: [
        '--lang=en-US,en',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--disable-gpu',
      ],
      noSandboxFlag: true,
      userDataDir: userDataDir.path,
      headless: !_displayBrowser,
      devTools: false,
    );

    // Update the default permissions like clipboard access.
    await _browser!.defaultBrowserContext
        .overridePermissions(_origin, [PermissionType.clipboardReadWrite]);
  }

  /// Creates a new page and setup overrides and tracking.
  Future<R> withPage<R>({
    required Future<R> Function(Page page) fn,
  }) async {
    await startBrowser();
    final page = await _browser!.newPage();
    _pageOriginExpando[page] = _origin;
    await page.setRequestInterception(true);
    if (_trackCoverage) {
      await page.coverage.startJSCoverage(resetOnNavigation: false);
      await page.coverage.startCSSCoverage(resetOnNavigation: false);
    }

    page.onRequest.listen((rq) async {
      // soft-abort
      if (rq.url.startsWith('https://www.google-analytics.com/') ||
          rq.url.startsWith('https://www.googletagmanager.com/') ||
          rq.url.startsWith('https://www.google.com/insights') ||
          rq.url.startsWith(
              'https://www.gstatic.com/brandstudio/kato/cookie_choice_component/')) {
        // reduce log error by replying with empty JS content
        if (rq.url.endsWith('.js') || rq.url.contains('.js?')) {
          await rq.respond(
            status: 200,
            body: '{}',
            contentType: 'application/javascript',
          );
        } else {
          await rq.abort(error: ErrorReason.failed);
        }
        return;
      }
      // ignore
      if (rq.url.startsWith('data:')) {
        await rq.continueRequest();
        return;
      }

      final uri = Uri.parse(rq.url);
      if (uri.path.contains('//')) {
        _serverErrors.add('Double-slash URL detected: "${rq.url}".');
      }

      await rq.continueRequest(headers: rq.headers);
    });

    page.onResponse.listen((rs) async {
      if (rs.status >= 500) {
        _serverErrors
            .add('${rs.status} ${rs.statusText} received on ${rs.request.url}');
      } else if (rs.status >= 400 && rs.url.contains('/static/')) {
        _serverErrors
            .add('${rs.status} ${rs.statusText} received on ${rs.request.url}');
      }

      final contentType = rs.headers[HttpHeaders.contentTypeHeader];
      if (contentType == null || contentType.isEmpty) {
        _serverErrors
            .add('Content type header is missing for ${rs.request.url}.');
      }
      if (rs.status == 200 && contentType!.contains('text/html')) {
        try {
          parseAndValidateHtml(await rs.text);
        } catch (e) {
          _serverErrors.add('${rs.request.url} returned bad HTML: $e');
        }
      }

      final uri = Uri.parse(rs.url);
      if (uri.pathSegments.length > 1 && uri.pathSegments.first == 'static') {
        if (!uri.pathSegments[1].startsWith('hash-')) {
          _serverErrors.add('Static ${rs.url} is without hash URL.');
        }

        final cacheHeader = rs.headers[HttpHeaders.cacheControlHeader];
        if (cacheHeader == null ||
            !cacheHeader.contains('public') ||
            !cacheHeader.contains('max-age')) {
          _serverErrors.add('Static ${rs.url} is without public caching.');
        }
      }
    });

    // print console messages
    page.onConsole.listen(print);

    // print and store uncaught errors
    page.onError.listen((e) {
      if (e.toString().contains(
          'FocusTrap: Element must have at least one focusable child.')) {
        // The error seems to come from material components, but it still works.
        // TODO: investigate if this is something we can change on our side.
        print('Ignored client error: $e');
        return;
      } else {
        print('Client error: $e');
        _clientErrors.add(e);
      }
    });

    _trackedPages.add(page);

    try {
      return await fn(page);
    } finally {
      await _closePage(page);
      _verifyErrors();
    }
  }

  /// Gets tracking results of [page] and closes it.
  Future<void> _closePage(Page page) async {
    if (_trackCoverage) {
      final jsEntries = await page.coverage.stopJSCoverage();
      for (final e in jsEntries) {
        _jsCoverages[e.url] ??= _Coverage(e.url);
        _jsCoverages[e.url]!.textLength = e.text.length;
        _jsCoverages[e.url]!.addRanges(e.ranges);
      }

      final cssEntries = await page.coverage.stopCSSCoverage();
      for (final e in cssEntries) {
        _cssCoverages[e.url] ??= _Coverage(e.url);
        _cssCoverages[e.url]!.textLength = e.text.length;
        _cssCoverages[e.url]!.addRanges(e.ranges);
      }
    }

    await page.close();
    _trackedPages.remove(page);
  }

  void _verifyErrors() {
    if (_clientErrors.isNotEmpty) {
      throw Exception('Client errors detected: ${_clientErrors.first}');
    }
    if (_serverErrors.isNotEmpty) {
      throw Exception('Server errors detected: ${_serverErrors.first}');
    }
  }

  Future<void> close() async {
    if (_trackedPages.isNotEmpty) {
      throw StateError('There are tracked pages with pending coverage report.');
    }
    await _browser!.close();

    _printCoverage();
    if (_coverageDir != null) {
      await _saveCoverage(p.join(_coverageDir!, 'puppeteer'));
    }
    await _tempDir.delete(recursive: true);
  }

  void _printCoverage() {
    for (final c in _jsCoverages.values) {
      print('${c.url}: ${c.percent.toStringAsFixed(2)}%');
    }
    for (final c in _cssCoverages.values) {
      print('${c.url}: ${c.percent.toStringAsFixed(2)}%');
    }
  }

  Future<void> _saveCoverage(String outputDir) async {
    Future<void> saveToFile(Map<String, _Coverage> map, String path) async {
      if (map.isNotEmpty) {
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString(json.encode(map.map(
          (k, v) => MapEntry<String, dynamic>(
            v.url,
            {
              'textLength': v.textLength,
              'ranges': v._coveredRanges.map((r) => r.toJson()).toList(),
            },
          ),
        )));
      }
    }

    final outputFileName = _testName ?? _generateTestName();
    await saveToFile(_jsCoverages, '$outputDir/$outputFileName.js.json');
    await saveToFile(_cssCoverages, '$outputDir/$outputFileName.css.json');
  }
}

String _generateTestName() {
  return [
    p.basenameWithoutExtension(Platform.script.path),
    DateTime.now().microsecondsSinceEpoch,
    ProcessInfo.currentRss,
  ].join('-');
}

/// Stores the origin URL on the page.
final _pageOriginExpando = Expando<String>();

extension PageExt on Page {
  /// The base URL of the pub.dev website.
  String get origin => _pageOriginExpando[this]!;

  /// Visits the [path] relative to the origin.
  Future<Response> gotoOrigin(String path) async {
    return await goto('$origin$path', wait: Until.networkIdle);
  }

  /// Returns the [property] value of the first elemented by [selector].
  Future<String> propertyValue(String selector, String property) async {
    final h = await $(selector);
    return await h.propertyValue(property);
  }
}

extension ElementHandleExt on ElementHandle {
  Future<String> textContent() async {
    return await propertyValue('textContent');
  }

  Future<String?> attributeValue(String name) async {
    final v = await evaluate('el => el.getAttribute("$name")');
    return v as String?;
  }
}

/// Track the covered ranges in the source file.
class _Coverage {
  final String url;
  int? textLength;

  /// List of start-end ranges that were covered in the source file during the
  /// execution of the app.
  List<Range> _coveredRanges = <Range>[];

  _Coverage(this.url);

  void addRanges(List<Range> ranges) {
    final list = [..._coveredRanges, ...ranges];
    // sort by start position first, and if they are matching, sort by end position
    list.sort((a, b) {
      final x = a.start.compareTo(b.start);
      return x == 0 ? a.end.compareTo(b.end) : x;
    });
    // merge ranges
    _coveredRanges = list.fold<List<Range>>(<Range>[], (m, range) {
      if (m.isEmpty || m.last.end < range.start) {
        m.add(range);
      } else {
        final last = m.removeLast();
        m.add(Range(last.start, range.end));
      }
      return m;
    });
  }

  double get percent {
    final coveredPosition =
        _coveredRanges.fold<int>(0, (sum, r) => sum + r.end - r.start);
    return coveredPosition * 100 / textLength!;
  }
}

/// User to inject in the fake google auth JS script.
class FakeGoogleUser {
  final String? id;
  final String? email;
  final String? imageUrl;
  final String? accessToken;
  final String? idToken;
  final String? scope;
  final DateTime? expiresAt;

  FakeGoogleUser({
    this.id,
    this.email,
    this.imageUrl,
    this.accessToken,
    this.idToken,
    this.scope,
    this.expiresAt,
  });

  factory FakeGoogleUser.withDefaults(String email) {
    final id = email.replaceAll('@', '-at-').replaceAll('.', '-dot-');
    return FakeGoogleUser(
      id: id,
      email: email,
      imageUrl: '/images/user/$id.jpg',
      scope: 'profile',
      accessToken: id,
      idToken: id,
      expiresAt: DateTime.now().add(Duration(hours: 1)),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'isSignedIn': id != null,
        'id': id,
        'email': email,
        'imageUrl': imageUrl,
        'accessToken': accessToken,
        'idToken': idToken,
        'expiresAt': expiresAt?.millisecondsSinceEpoch ?? 0,
      };
}
