// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../shared/datastore.dart' as db;

/// A secret value stored in Datastore, typically an access credential used by
/// the application.
@db.Kind(name: 'Secret', idType: db.IdType.String)
class Secret extends db.Model {
  @db.StringProperty(required: true)
  String value;
}

/// Identifiers of the [Secret] keys.
abstract class SecretKey {
  static const String redisConnectionString = 'redis.connectionString';

  /// OAuth audiences have separate secrets for each audience.
  static const String oauthPrefix = 'oauth.secret-';

  /// Site-wide announcement.
  static const String announcement = 'announcement';

  /// JSON-encoded list of Strings that will be considered as spam.
  static const String spamWords = 'spam-words';

  /// JSON-encoded list of URLs from which scripts is allowed in the
  /// Content-Security-Policy header.
  static const String cspScriptUrls = 'csp-script-urls';

  /// The restriction applied on uploads.
  ///
  /// This feature is intended as an emergency break.
  ///
  /// Valid values for `upload-restriction` are:
  ///  * `no-uploads`, no package publications will be accepted by the server,
  ///  * `only-updates`, publication of new packages will not be accepted, but new versions of existing packages will be accepted, and,
  ///  * `no-restriction`, (default) publication of new packages and new versions is allowed.
  static const String uploadRestriction = 'upload-restriction';

  /// List of all keys.
  static const values = [
    redisConnectionString,
    announcement,
    spamWords,
    uploadRestriction,
    cspScriptUrls,
  ];

  /// Whether the key is valid.
  static bool isValid(String key) {
    if (values.contains(key)) return true;
    if (key.startsWith(oauthPrefix)) return true;
    return false;
  }
}
