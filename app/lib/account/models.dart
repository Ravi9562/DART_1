// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:gcloud/db.dart' as db;
import 'package:meta/meta.dart';
import 'package:ulid/ulid.dart';

/// User data model with a random UUID id.
@db.Kind(name: 'User', idType: db.IdType.String)
class User extends db.ExpandoModel {
  /// Same as [id].
  /// A random UUID id.
  String get userId => id as String;

  @db.StringProperty()
  String oauthUserId;

  @db.StringProperty()
  String email;

  @db.DateTimeProperty()
  DateTime created;
}

/// Maps Oauth user_id to User.id
@db.Kind(name: 'OAuthUserID', idType: db.IdType.String)
class OAuthUserID extends db.ExpandoModel {
  /// Same as [id].
  String get oauthUserId => id as String;

  @db.ModelKeyProperty(required: true)
  db.Key userIdKey;

  String get userId => userIdKey.id as String;
}

/// Derived data for [User] for fast lookup.
@db.Kind(name: 'UserInfo', idType: db.IdType.String)
class UserInfo extends db.ExpandoModel {
  String get userId => id as String;

  @db.StringListProperty()
  List<String> packages = <String>[];

  @db.StringListProperty()
  List<String> publishers = <String>[];

  @db.DateTimeProperty()
  DateTime updated;
}

/// An active consent request sent to the recipient [User] (the parent entity).
@db.Kind(name: 'Consent', idType: db.IdType.String)
class Consent extends db.Model {
  /// The consent id.
  String get consentId => id as String;

  /// The user that this consent is for.
  String get userId => parentKey.id as String;

  /// A [Uri.path]-like concatenation of identifiers from [kind] and [args].
  /// It should be used to query the Datastore for duplicate detection.
  @db.StringProperty()
  String dedupId;

  @db.StringProperty()
  String kind;

  @db.StringListProperty()
  List<String> args;

  @db.StringProperty()
  String fromUserId;

  @db.DateTimeProperty()
  DateTime created;

  @db.DateTimeProperty()
  DateTime expires;

  @db.DateTimeProperty()
  DateTime lastNotified;

  @db.IntProperty()
  int notificationCount;

  Consent();

  Consent.init({
    @required db.Key parentKey,
    @required this.kind,
    @required this.args,
    @required this.fromUserId,
    Duration timeout = const Duration(days: 7),
  }) {
    this.parentKey = parentKey;
    this.id = Ulid().toString();
    dedupId = consentDedupId(kind, args);
    created = DateTime.now().toUtc();
    notificationCount = 0;
    expires = created.add(timeout);
  }

  bool isExpired() => DateTime.now().toUtc().isAfter(expires);

  /// The timestamp when the next notification could be sent out.
  DateTime get nextNotification =>
      (lastNotified ?? created).add(Duration(minutes: 1 << notificationCount));

  /// Whether a new notification should be sent.
  bool shouldNotify() =>
      notificationCount == 0 ||
      DateTime.now().toUtc().isAfter(nextNotification);
}

/// Calculates the dedupId of a consent request.
String consentDedupId(String kind, List<String> args) =>
    [kind, ...args].map(Uri.encodeComponent).join('/');
