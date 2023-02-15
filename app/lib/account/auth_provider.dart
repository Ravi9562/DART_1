// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../service/openid/jwt.dart';

class AuthResult {
  final String oauthUserId;
  final String email;
  final String audience;
  final String? nonce;
  final String? name;
  final String? imageUrl;

  AuthResult({
    required this.oauthUserId,
    required this.email,
    required this.audience,
    this.nonce,
    this.name,
    this.imageUrl,
  });
}

class AccountProfile {
  final String? name;
  final String? imageUrl;

  AccountProfile({
    required this.name,
    required this.imageUrl,
  });
}

/// Authenticates bearer tokens from the `'authentication: bearer'` header.
abstract class AuthProvider {
  /// Parses and verifies [token] - if issued by an external service
  /// targeting `pub.dev`.
  Future<JsonWebToken?> tryAuthenticateAsServiceToken(String token);

  /// Checks the [token] and returns a verified user information.
  ///
  /// Returns null on any error, or if the token is expired, or the user is not
  /// verified.
  Future<AuthResult?> tryAuthenticateAsUser(String token);

  /// Returns the profile information of a given access token.
  Future<AccountProfile?> getAccountProfile(String? accessToken);

  /// Returns the URL that the user should visit for authentication.
  Future<Uri> getOauthAuthenticationUrl({
    required String state,
    required String nonce,
  });

  /// Returns the OAuth2 profile information using the authentication [code].
  Future<AuthResult?> tryAuthenticateOauthCode({
    required String code,
  });

  /// Close resources.
  Future<void> close();
}
