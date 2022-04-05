// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:http/http.dart' as http;
import 'package:http_retry/http_retry.dart';

final _transientStatusCodes = {
  // See: https://cloud.google.com/storage/docs/xml-api/reference-status
  429,
  500,
  503,
};

/// Creates a HTTP client that retries transient status codes.
http.Client httpRetryClient({
  http.Client? innerClient,
  int? retries,
}) {
  return _MultiCloseClient(RetryClient(
    innerClient ?? http.Client(),
    when: (r) => _transientStatusCodes.contains(r.statusCode),
    // TOOD: Consider implementing whenError and handle DNS + handshake errors.
    //       These are safe, retrying after partially sending data is more
    //       sketchy, but probably safe in our application.
    retries: retries ?? 5,
  ));
}

/// Returns an [http.Client] which sends a `Bearer` token as `Authorization`
/// header for each request.
http.Client httpClientWithAuthorization({
  required Future<String?> Function() tokenProvider,
  http.Client? client,
}) {
  return _MultiCloseClient(_AuthenticatedClient(
    tokenProvider,
    client ?? http.Client(),
    client == null,
  ));
}

/// An [http.Client] which sends a `Bearer` token as `Authorization` header for
/// each request.
class _AuthenticatedClient extends http.BaseClient {
  final Future<String?> Function() _tokenProvider;
  final http.Client _client;
  final bool _closeInnerClient;

  _AuthenticatedClient(
      this._tokenProvider, this._client, this._closeInnerClient);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _tokenProvider();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return await _client.send(request);
  }

  @override
  void close() {
    if (_closeInnerClient) {
      _client.close();
    }
    super.close();
  }
}

/// Allows the call of [close] multiple times without throwing an Exception.
class _MultiCloseClient extends http.BaseClient {
  final http.Client _inner;
  bool _isClosing = false;

  _MultiCloseClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return await _inner.send(request);
  }

  @override
  void close() {
    if (_isClosing) return;
    _isClosing = true;
    _inner.close();
    super.close();
  }
}
