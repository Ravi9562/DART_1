// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart' as yaml;

part 'models.g.dart';

/// The configuration to use when creating a local (partial) mirror of pub.dev
/// in order to us it in tests.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class TestProfile {
  final List<TestPackage> packages;
  final List<TestPublisher> publishers;
  final List<TestUser> users;

  /// The email address of the default user.
  final String defaultUser;

  TestProfile({
    @required List<TestPackage> packages,
    List<TestPublisher> publishers,
    List<TestUser> users,
    this.defaultUser,
  })  : packages = packages ?? <TestPackage>[],
        publishers = publishers ?? <TestPublisher>[],
        users = users ?? <TestUser>[];

  factory TestProfile.fromJson(Map<String, dynamic> json) =>
      _$TestProfileFromJson(json);

  factory TestProfile.fromYaml(String source) {
    final map = json.decode(json.encode(yaml.loadYaml(source)));
    return TestProfile.fromJson(map as Map<String, dynamic>);
  }

  Map<String, dynamic> toJson() => _$TestProfileToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class TestPackage {
  final String name;
  final List<String> uploaders;
  final String publisher;
  final List<String> versions;
  final bool isDiscontinued;
  final String replacedBy;
  final bool isUnlisted;

  TestPackage({
    this.name,
    this.uploaders,
    this.publisher,
    this.versions,
    this.isDiscontinued,
    this.replacedBy,
    this.isUnlisted,
  });

  factory TestPackage.fromJson(Map<String, dynamic> json) =>
      _$TestPackageFromJson(json);

  Map<String, dynamic> toJson() => _$TestPackageToJson(this);

  TestPackage change({
    List<String> uploaders,
    List<String> versions,
  }) {
    return TestPackage(
      name: name,
      uploaders: uploaders ?? this.uploaders,
      publisher: publisher,
      versions: versions ?? this.versions,
    );
  }
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class TestPublisher {
  final String name;
  final DateTime created;
  final DateTime updated;
  final List<TestMember> members;

  TestPublisher({
    @required this.name,
    this.created,
    this.updated,
    @required List<TestMember> members,
  }) : members = members ?? <TestMember>[];

  factory TestPublisher.fromJson(Map<String, dynamic> json) =>
      _$TestPublisherFromJson(json);

  Map<String, dynamic> toJson() => _$TestPublisherToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class TestMember {
  final String email;
  final String role;
  final DateTime created;
  final DateTime updated;

  TestMember({
    @required this.email,
    @required this.role,
    this.created,
    this.updated,
  });

  factory TestMember.fromJson(Map<String, dynamic> json) =>
      _$TestMemberFromJson(json);

  Map<String, dynamic> toJson() => _$TestMemberToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class TestUser {
  final String email;
  final String oauthUserId;
  final DateTime created;
  final bool isDeleted;
  final bool isBlocked;

  /// The list of package names that the user liked.
  final List<String> likes;

  TestUser({
    @required this.email,
    this.oauthUserId,
    this.created,
    this.isDeleted,
    this.isBlocked,
    @required List<String> likes,
  }) : likes = likes ?? <String>[];

  factory TestUser.fromJson(Map<String, dynamic> json) =>
      _$TestUserFromJson(json);

  Map<String, dynamic> toJson() => _$TestUserToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ResolvedVersion implements Comparable<ResolvedVersion> {
  final String package;
  final String version;
  final DateTime created;

  ResolvedVersion({
    @required this.package,
    @required this.version,
    @required this.created,
  });

  factory ResolvedVersion.fromJson(Map<String, dynamic> json) =>
      _$ResolvedVersionFromJson(json);

  Map<String, dynamic> toJson() => _$ResolvedVersionToJson(this);

  @override
  int compareTo(ResolvedVersion other) => created.compareTo(other.created);
}
