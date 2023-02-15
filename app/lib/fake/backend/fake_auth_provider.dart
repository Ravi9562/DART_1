// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:googleapis/oauth2/v2.dart' as oauth2_v2;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:pub_dev/account/default_auth_provider.dart';
import 'package:pub_dev/service/openid/gcp_openid.dart';
import 'package:pub_dev/service/openid/openid_models.dart';

import '../../account/auth_provider.dart';
import '../../service/openid/github_openid.dart';
import '../../service/openid/jwt.dart';

/// A fake auth provider where user resolution is done via the provided access
/// token.
///
/// Access tokens are in the format of user-name-at-example-dot-com and resolve
/// to user-name@example.com as email and user-name-example-com as userId.
///
/// Access tokens without '-at-' are not resolving to any user.
class FakeAuthProvider extends BaseAuthProvider {
  @override
  Future<void> close() async {}

  @override
  Future<oauth2_v2.Userinfo> callGetUserinfo({
    required String accessToken,
  }) {
    // Since we don't use getAccountProfile from the base class, this method
    // won't get called.
    throw AssertionError();
  }

  @override
  Future<oauth2_v2.Tokeninfo> callTokenInfoWithAccessToken({
    required String accessToken,
  }) async {
    final token = JsonWebToken.tryParse(accessToken);
    if (token == null) {
      throw oauth2_v2.ApiRequestError(null);
    }
    final goodSignature = await verifyTokenSignature(
        token: token, openIdDataFetch: () async => throw AssertionError());
    if (!goodSignature) {
      throw oauth2_v2.ApiRequestError(null);
    }
    return oauth2_v2.Tokeninfo(
      audience: token.payload.aud.single,
      email: token.payload['email'] as String?,
      scope: token.payload['scope'] as String?,
      userId: token.payload['sub'] as String?,
    );
  }

  @override
  Future<http.Response> callTokenInfoWithIdToken({
    required String idToken,
  }) async {
    final token = JsonWebToken.tryParse(idToken);
    if (token == null) {
      return http.Response(json.encode({}), 400);
    }
    final goodSignature = await verifyTokenSignature(
        token: token, openIdDataFetch: () async => throw AssertionError());
    if (!goodSignature) {
      return http.Response(json.encode({}), 400);
    }
    return http.Response(
        json.encode({
          ...token.header,
          ...token.payload,
          'email_verified': true,
        }),
        200);
  }

  @override
  Future<bool> verifyTokenSignature({
    required JsonWebToken token,
    required Future<OpenIdData> Function() openIdDataFetch,
  }) async {
    return base64.encode(token.signature) ==
        base64.encode(utf8.encode('valid'));
  }

  @override
  Future<AuthResult?> tryAuthenticateAsUser(String accessToken) async {
    late String jwtTokenValue;
    if (accessToken.contains('-at-') &&
        !JsonWebToken.looksLikeJWT(accessToken)) {
      final uri = Uri.tryParse(accessToken);
      if (uri == null) {
        return null;
      }
      final email = uri.path.replaceAll('-at-', '@').replaceAll('-dot-', '.');
      final audience = uri.queryParameters['aud'] ?? 'fake-site-audience';
      jwtTokenValue = _createGcpToken(
        email: email,
        audience: audience,
        signature: null,
      );
    } else {
      jwtTokenValue = accessToken;
    }
    return super.tryAuthenticateAsUser(jwtTokenValue);
  }

  @override
  Future<AccountProfile?> getAccountProfile(String? accessToken) async {
    if (accessToken == null) {
      return null;
    }
    final authResult = await tryAuthenticateAsUser(accessToken);
    if (authResult == null) {
      return null;
    }
    final email = authResult.email;

    // using the user part as name
    final name =
        email.split('@').first.replaceAll('-', ' ').replaceAll('.', ' ');

    // gravatar image with retro face
    final emailMd5 = md5.convert(utf8.encode(email.trim())).toString();
    final imageUrl = 'https://www.gravatar.com/avatar/$emailMd5?d=retro&s=200';

    return AccountProfile(
      name: name,
      imageUrl: imageUrl,
    );
  }

  @override
  Future<Uri> getOauthAuthenticationUrl({
    required String state,
    required String nonce,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult?> tryAuthenticateOauthCode({
    required String code,
  }) async {
    throw UnimplementedError();
  }
}

@visibleForTesting
String createFakeAuthTokenForEmail(
  String email, {
  String? audience,
}) {
  return Uri(
      path: email.replaceAll('.', '-dot-').replaceAll('@', '-at-'),
      queryParameters: {'aud': audience ?? 'fake-site-audience'}).toString();
}

@visibleForTesting
String createFakeServiceAccountToken({
  required String email,
  // `https://pub.dev` unless specified otherwise
  String? audience,
  // utf8-encoded `valid` unless specified otherwise
  List<int>? signature,
}) {
  return _createGcpToken(
    email: email,
    audience: audience ?? 'https://pub.dev',
    signature: signature,
  );
}

String _createGcpToken({
  required String email,
  required String audience,
  required List<int>? signature,
}) {
  final token = JsonWebToken(
    header: {
      'alg': 'RS256',
      'typ': 'JWT',
    },
    payload: {
      'email': email,
      'sub': _oauthUserIdFromEmail(email),
      'aud': audience,
      'iss': GcpServiceAccountJwtPayload.issuerUrl,
      ..._jwtPayloadTimestamps(),
    },
    signature: signature ?? utf8.encode('valid'),
  );
  return token.asEncodedString();
}

@visibleForTesting
String createFakeGithubActionToken({
  required String repository,
  required String ref,
  // `https://pub.dev` unless specified otherwise
  String? audience,

  // 'push' unless specified otherwise
  String? eventName,
  String? sha,
  String? actor,
  String? environment,
  // utf8-encoded `valid` unless specified otherwise
  List<int>? signature,
  String? runId,
  String? repositoryId,
  String? repositoryOwnerId,
}) {
  var refType = ref.split('/')[1];
  if (refType.endsWith('s')) {
    refType = refType.substring(0, refType.length - 1);
  }
  final token = JsonWebToken(
    header: {
      'alg': 'RS256',
      'typ': 'JWT',
    },
    payload: {
      'aud': audience ?? 'https://pub.dev',
      'repository': repository,
      'repository_id': repositoryId ?? repository.hashCode.abs().toString(),
      'repository_owner': repository.split('/').first,
      'repository_owner_id': repositoryOwnerId ??
          repository.split('/').first.hashCode.abs().toString(),
      'event_name': eventName ?? 'push',
      'ref': ref,
      'ref_type': refType,
      'iss': GitHubJwtPayload.issuerUrl,
      'run_id': runId ?? clock.now().millisecondsSinceEpoch.toString(),
      if (sha != null) 'sha': sha,
      if (actor != null) 'actor': actor,
      if (environment != null) 'environment': environment,
      ..._jwtPayloadTimestamps(),
    },
    signature: signature ?? utf8.encode('valid'),
  );
  return token.asEncodedString();
}

String _oauthUserIdFromEmail(String email) =>
    email.replaceAll('@', '-').replaceAll('.', '-');

Map<String, dynamic> _jwtPayloadTimestamps() {
  final now = clock.now();
  return <String, dynamic>{
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'nbf': now.millisecondsSinceEpoch ~/ 1000,
    'exp': now.add(Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000,
  };
}
