// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class AuthResult {
  final String oauthUserId;
  final String email;

  AuthResult(this.oauthUserId, this.email);
}

/// Authenticates bearer tokens from the `'authentication: bearer'` header.
abstract class AuthProvider {
  /// Returns the URL of the authorization endpoint.
  String authorizationUrl(String redirectUrl, String state);

  /// Validates the authorization [code], and returns the access token.
  ///
  /// Returns null on any error, or if the token is expired, or the code is not
  /// verified.
  Future<String> authCodeToAccessToken(String redirectUrl, String code);

  /// Checks the [token] and returns a verified user information.
  ///
  /// Returns null on any error, or if the token is expired, or the user is not
  /// verified.
  Future<AuthResult> tryAuthenticate(String token);

  /// Close resources.
  Future<void> close();
}
