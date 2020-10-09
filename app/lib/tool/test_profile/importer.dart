// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:basics/basics.dart';
import 'package:crypto/crypto.dart';
import 'package:gcloud/service_scope.dart';
import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'package:client_data/package_api.dart';

import '../../account/backend.dart';
import '../../account/models.dart';
import '../../package/backend.dart';
import '../../publisher/models.dart';
import '../../shared/datastore.dart';
import '../../shared/urls.dart' as urls;

import 'models.dart';
import 'resolver.dart';

/// Imports [profile] data into the Datastore.
@visibleForTesting
Future<void> importProfile({
  @required TestProfile profile,
  List<String> resolvedVersions,
  @required String archiveCachePath,
}) async {
  // resolve versions if they are not yet resolved
  if (resolvedVersions == null || resolvedVersions.isEmpty) {
    resolvedVersions = await resolveVersions(profile);
  }

  // create users
  for (final u in profile.users) {
    final oauthUserId = u.oauthUserId ?? _baseIdFromEmail(u.email);
    final userId = _userIdFromEmail(u.email);
    await dbService.commit(inserts: [
      User()
        ..id = userId
        ..oauthUserId = oauthUserId
        ..email = u.email
        ..created = u.created ?? DateTime.now().toUtc()
        ..isDeleted = u.isDeleted ?? false
        ..isBlocked = u.isBlocked ?? false,
      OAuthUserID()
        ..id = oauthUserId
        ..userIdKey = dbService.emptyKey.append(User, id: userId),
    ]);
  }

  // create publishers
  for (final p in profile.publishers) {
    await dbService.commit(inserts: [
      Publisher()
        ..id = p.name
        ..contactEmail = p.members.isEmpty ? null : p.members.first.email
        ..websiteUrl = 'https://${p.name}/'
        ..created = p.created ?? DateTime.now().toUtc()
        ..updated = p.updated ?? DateTime.now().toUtc()
        ..isAbandoned = false,
      ...p.members.map(
        (m) => PublisherMember()
          ..parentKey = dbService.emptyKey.append(Publisher, id: p.name)
          ..id = _userIdFromEmail(m.email)
          ..userId = _userIdFromEmail(m.email)
          ..created = m.created ?? DateTime.now().toUtc()
          ..updated = m.updated ?? DateTime.now().toUtc()
          ..role = PublisherMemberRole.admin,
      )
    ]);
  }

  // create packages
  Client client;
  final archiveCacheDir = Directory(archiveCachePath);
  await archiveCacheDir.create(recursive: true);
  for (final rv in resolvedVersions) {
    final parts = rv.partition(':');
    final packageName = parts.first;
    final versionName = parts.last;

    final fileName = rv.replaceAll(':', '-') + '.tar.gz';
    final file = File(p.join(archiveCacheDir.path, fileName));
    // download package archive if not already in the cache
    if (!await file.exists()) {
      client ??= Client();
      final rs = await client.get(
          '${urls.siteRoot}${urls.pkgArchiveDownloadUrl(packageName, versionName)}');
      await file.writeAsBytes(rs.bodyBytes);
    }

    // figure out the active user
    final uploaderEmails = _potentialActiveEmails(profile, packageName);
    final uploaderEmail =
        uploaderEmails[rv.hashCode.abs() % uploaderEmails.length];
    final activeUser =
        await accountBackend.lookupUserById(_userIdFromEmail(uploaderEmail));

    // upload package in the name of the active user
    await fork(() async {
      registerAuthenticatedUser(activeUser);
      // ignore: invalid_use_of_visible_for_testing_member
      await packageBackend.upload(file.openRead());

      final publisherId = _publisherOf(profile, packageName);
      if (publisherId != null) {
        await packageBackend.setPublisher(
          packageName,
          PackagePublisherInfo(publisherId: publisherId),
        );
      }
    });
  }
  client?.close();

  // create likes
  for (final u in profile.users) {
    if (u.likes == null || u.likes.isEmpty) continue;
    final userId = _userIdFromEmail(u.email);
    await dbService.commit(inserts: [
      ...u.likes.map(
        (p) => Like()
          ..parentKey = dbService.emptyKey.append(User, id: userId)
          ..id = p
          // TODO: support via [TestProfile]
          ..created = DateTime.now().toUtc()
          ..packageName = p,
      )
    ]);
  }
}

List<String> _potentialActiveEmails(TestProfile profile, String packageName) {
  final testPackage = profile.packages
      .firstWhere((p) => p.name == packageName, orElse: () => null);

  // no test package specification
  if (testPackage == null) return [profile.defaultUser];

  // uploaders
  if (testPackage.publisher == null) return testPackage.uploaders;

  // publisher
  print([testPackage.publisher, profile.publishers.map((p) => p.name)]);
  final members = profile.publishers
      .firstWhere((p) => p.name == testPackage.publisher)
      .members;
  return members.map((m) => m.email).toList();
}

String _publisherOf(TestProfile profile, String packageName) {
  final testPackage = profile.packages
      .firstWhere((p) => p.name == packageName, orElse: () => null);
  return testPackage?.publisher;
}

String _baseIdFromEmail(String email) =>
    email.replaceAll('.', '-dot-').replaceAll('@', '-at-');

String _userIdFromEmail(String email) {
  final hash = sha1.convert(utf8.encode('email-$email')).toString();
  return hash.substring(0, 8) +
      '-' +
      hash.substring(8, 12) +
      '-' +
      hash.substring(12, 16) +
      '-' +
      hash.substring(16, 20) +
      '-' +
      hash.substring(20, 32);
}
