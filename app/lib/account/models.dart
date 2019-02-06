// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:gcloud/db.dart' as db;

/// User data model.
@db.Kind(name: 'User', idType: db.IdType.String)
class User extends db.ExpandoModel {
  String get userId => id as String;

  @db.StringProperty()
  String oauthUserId;

  @db.StringProperty()
  String email;

  @db.BoolProperty()
  bool hideEmail = false;

  @db.DateTimeProperty()
  DateTime created;
}

/// Maps Oauth user_id to User.id
@db.Kind(name: 'OAuthUserID', idType: db.IdType.String)
class OAuthUserID extends db.ExpandoModel {
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
