// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:_pub_shared/data/package_api.dart';
import 'package:clock/clock.dart';
import 'package:gcloud/service_scope.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../../frontend/handlers/pubapi.client.dart';
import '../../service/services.dart';
import '../../shared/configuration.dart';
import 'http.dart';

/// Creates an API client with [authToken], [sessionId] and/or
/// [csrfToken] that uses the configured HTTP endpoints.
///
/// Services scopes are used to automatically close the client once we exit the current scope.
@visibleForTesting
PubApiClient createPubApiClient({
  String? authToken,
  String? sessionId,
  String? csrfToken,
}) {
  final httpClient = httpClientWithAuthorization(
    tokenProvider: () async => authToken,
    sessionIdProvider: () async => sessionId,
    csrfTokenProvider: () async => csrfToken,
  );
  registerScopeExitCallback(() async => httpClient.close());
  return PubApiClient(
    activeConfiguration.primaryApiUri!.toString(),
    client: _FakeTimeClient(httpClient),
  );
}

class _FakeTimeClient implements http.Client {
  final http.Client _client;
  _FakeTimeClient(this._client);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers[fakeClockHeaderName] = clock.now().toIso8601String();
    return _client.send(request);
  }

  @override
  void close() => _client.close();

  @override
  Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _client.delete(url, headers: headers, body: body, encoding: encoding);

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _client.get(url, headers: headers);

  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
      _client.head(url, headers: headers);

  @override
  Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _client.patch(url, headers: headers, body: body, encoding: encoding);

  @override
  Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _client.post(url, headers: headers, body: body, encoding: encoding);

  @override
  Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _client.put(url, headers: headers, body: body, encoding: encoding);

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) =>
      _client.read(url, headers: headers);

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) =>
      _client.readBytes(url, headers: headers);
}

/// Creates a pub.dev API client and executes [fn], making sure that the HTTP
/// resources are freed after the callback finishes.
///
/// If [bearerToken], [sessionId] or [csrfToken] is specified, the corresponding
/// HTTP header will be sent alongside the request.
Future<R> withHttpPubApiClient<R>({
  String? bearerToken,
  String? sessionId,
  String? csrfToken,
  String? pubHostedUrl,
  required Future<R> Function(PubApiClient client) fn,
}) async {
  final httpClient = httpClientWithAuthorization(
    tokenProvider: () async => bearerToken,
    sessionIdProvider: () async => sessionId,
    csrfTokenProvider: () async => csrfToken,
  );
  try {
    final apiClient = PubApiClient(
      pubHostedUrl ?? activeConfiguration.primaryApiUri!.toString(),
      client: httpClient,
    );
    return await fn(apiClient);
  } finally {
    httpClient.close();
  }
}

extension PubApiClientExt on PubApiClient {
  @visibleForTesting
  Future<String> preparePackageUpload(List<int> bytes) async {
    final uploadInfo = await getPackageUploadUrl();

    final uri = Uri.parse(uploadInfo.url);
    final request = http.MultipartRequest('POST', uri)
      ..headers[fakeClockHeaderName] = clock.now().toIso8601String()
      ..fields.addAll(uploadInfo.fields!)
      ..files.add(http.MultipartFile.fromBytes('file', bytes))
      ..followRedirects = false;
    final uploadRs = await request.send();
    if (uploadRs.statusCode != 303) {
      // NOTE: There are tests that fail with this on CI.
      // TODO: figure out what is causing these issues.
      final body = await uploadRs.stream.bytesToString();
      final headers = uploadRs.headers;

      var debugContent = '';
      try {
        final rs2 = await http.get(uri.replace(path: '/', queryParameters: {}));
        debugContent += '\nROOT: ${rs2.body}';
      } catch (e, st) {
        debugContent += '$e\n$st';
      }

      throw AssertionError('Expected HTTP redirect, got ${uploadRs.statusCode}.'
          '\nbody: $body\nheaders: $headers\n$debugContent');
    }

    final callbackUri =
        Uri.parse(uploadInfo.fields!['success_action_redirect']!);
    return callbackUri.queryParameters['upload_id']!;
  }

  @visibleForTesting
  Future<SuccessMessage> uploadPackageBytes(List<int> bytes) async {
    final uploadId = await preparePackageUpload(bytes);
    return await finishPackageUpload(uploadId);
  }
}
