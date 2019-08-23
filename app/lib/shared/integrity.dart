// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:gcloud/db.dart';
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';

import '../account/models.dart';
import '../package/models.dart';

import 'email.dart' show isValidEmail;

final _logger = Logger('integrity.check');

/// Checks the integrity of the datastore.
class IntegrityChecker {
  final DatastoreDB _db;
  final int _concurrency;
  final _problems = <String>[];

  final _userToOauth = <String, String>{};
  final _oauthToUser = <String, String>{};
  final _emailToUser = <String, List<String>>{};
  final _invalidUsers = Set<String>();
  final _packages = <String>{};
  final _packagesWithVersion = <String>{};
  int _packageChecked = 0;
  int _versionChecked = 0;

  IntegrityChecker(this._db, {int concurrency})
      : _concurrency = concurrency ?? 1;

  /// Runs integrity checks, and reports the list of problems.
  Future<List<String>> check({bool ignorePackages = false}) async {
    await _checkUsers();
    await _checkOAuthUserIDs();
    if (!ignorePackages) {
      await _checkPackages();
      await _checkVersions();
    }
    // TODO: check Publishers, PublisherMembers
    return _problems;
  }

  Future _checkUsers() async {
    _logger.info('Scanning Users...');
    await for (User user in _db.query<User>().run()) {
      _userToOauth[user.userId] = user.oauthUserId;
      if (user.email == null ||
          user.email.isEmpty ||
          !isValidEmail(user.email)) {
        _problems.add('User(${user.userId}) has invalid e-mail: ${user.email}');
        _invalidUsers.add(user.userId);
      }
      if (user.email != null && user.email.isNotEmpty) {
        _emailToUser.putIfAbsent(user.email, () => []).add(user.userId);
      }
      // TODO: check if deleted user has no OAuthUserID entry
      // TODO: check if deleted user has only the minimal set of attributes
    }
    int badEmailToUserMappingCount = 0;
    _emailToUser.forEach((email, userIds) {
      if (userIds.length > 1) {
        badEmailToUserMappingCount++;
        _problems.add(
            'E-mail address $email is present at ${userIds.length} User: ${userIds.join(', ')}');
      }
    });
    if (badEmailToUserMappingCount > 0) {
      _problems.add(
          '$badEmailToUserMappingCount e-mail addresses have more than one User entity.');
    }
  }

  Future _checkOAuthUserIDs() async {
    _logger.info('Scanning OAuthUserIDs...');
    await for (OAuthUserID mapping in _db.query<OAuthUserID>().run()) {
      if (mapping.userIdKey == null || mapping.userId == null) {
        _problems
            .add('OAuthUserID(${mapping.oauthUserId}) has invalid userId.');
      }
      _oauthToUser[mapping.oauthUserId] = mapping.userId;
    }

    for (String userId in _userToOauth.keys) {
      final oauthUserId = _userToOauth[userId];
      // Migrated users without login are OK.
      if (oauthUserId == null) {
        continue;
      }
      final pointer = _oauthToUser[oauthUserId];
      if (pointer == null) {
        _problems.add(
            'User($userId) points to OAuthUserID($oauthUserId) but has no mapping.');
      } else if (pointer != userId) {
        _problems.add(
            'User($userId) points to OAuthUserID($oauthUserId) but it points to a different one ($pointer).');
      }
    }

    for (String oauthUserId in _oauthToUser.keys) {
      final userId = _oauthToUser[oauthUserId];
      if (userId == null) {
        _problems.add('OAuthUserID($oauthUserId) has no user.');
      }
      final pointer = _userToOauth[userId];
      if (pointer == null) {
        _problems.add(
            'User($userId) is mapped from OAuthUserID($oauthUserId), but does not have it set.');
      } else if (pointer != oauthUserId) {
        _problems.add(
            'User($userId) is mapped from OAuthUserID($oauthUserId), but points to a different one ($pointer).');
      }
    }
  }

  Future _checkPackages() async {
    _logger.info('Scanning Packages...');
    final pool = Pool(_concurrency);
    final futures = <Future>[];
    await for (Package p in _db.query<Package>().run()) {
      final f = pool.withResource(() => _checkPackage(p));
      futures.add(f);
    }
    await Future.wait(futures);
    await pool.close();
  }

  Future _checkPackage(Package p) async {
    _packages.add(p.name);
    if (p.uploaders == null || p.uploaders.isEmpty) {
      // TODO: empty uploaders with Publisher is fine
      // TODO: empty uploaders without Publisher must mark it as discontinued
      // TODO: empty uploaders with abandoned Publisher must mark it as discontinued
      _problems.add('Package(${p.name}) has no uploaders.');
    }
    for (String userId in p.uploaders) {
      if (!_userToOauth.containsKey(userId)) {
        _problems.add('Package(${p.name}) has uploader without User: $userId');
      }
      if (_invalidUsers.contains(userId)) {
        _problems.add('Package(${p.name}) has invalid uploader: User($userId)');
      }
    }
    final versionKeys = <Key>{};
    final qualifiedVersionKeys = <QualifiedVersionKey>{};
    await for (PackageVersion pv
        in _db.query<PackageVersion>(ancestorKey: p.key).run()) {
      versionKeys.add(pv.key);
      qualifiedVersionKeys.add(pv.qualifiedVersionKey);
      if (pv.uploader == null) {
        _problems.add(
            'PackageVersion(${pv.package} ${pv.version}) has no uploader.');
      }
      if (!_userToOauth.containsKey(pv.uploader)) {
        _problems.add(
            'PackageVersion(${pv.package} ${pv.version}) has uploader without User: ${pv.uploader}');
      }
      if (_invalidUsers.contains(pv.uploader)) {
        _problems.add(
            'PackageVersion(${pv.package} ${pv.version}) has invalid uploader: User(${pv.uploader})');
      }
    }
    if (p.latestVersionKey != null &&
        !versionKeys.contains(p.latestVersionKey)) {
      _problems.add(
          'Package(${p.name}) has missing latestVersionKey: ${p.latestVersionKey.id}');
    }
    if (p.latestDevVersionKey != null &&
        !versionKeys.contains(p.latestDevVersionKey)) {
      _problems.add(
          'Package(${p.name}) has missing latestDevVersionKey: ${p.latestDevVersionKey.id}');
    }

    // Checking if PackageVersionPubspec is referenced by a PackageVersion entity.
    final pvpQuery = _db.query<PackageVersionPubspec>()
      ..filter('package =', p.name);
    final pvpKeys = <QualifiedVersionKey>{};
    await for (PackageVersionPubspec pvp in pvpQuery.run()) {
      final key = pvp.qualifiedVersionKey;
      pvpKeys.add(key);
      if (!qualifiedVersionKeys.contains(key)) {
        _problems.add('PackageVersionPubspec($key) has no PackageVersion.');
      }
    }
    for (QualifiedVersionKey key in qualifiedVersionKeys) {
      if (!pvpKeys.contains(key)) {
        _problems.add('PackageVersion($key) has no PackageVersionPubspec.');
      }
    }

    // Checking if PackageVersionInfo is referenced by a PackageVersion entity.
    final pviQuery = _db.query<PackageVersionInfo>()
      ..filter('package =', p.name);
    final pviKeys = <QualifiedVersionKey>{};
    await for (PackageVersionInfo pvi in pviQuery.run()) {
      final key = pvi.qualifiedVersionKey;
      pviKeys.add(key);
      if (!qualifiedVersionKeys.contains(key)) {
        _problems.add('PackageVersionInfo($key) has no PackageVersion.');
      }
    }
    for (QualifiedVersionKey key in qualifiedVersionKeys) {
      if (!pviKeys.contains(key)) {
        _problems.add('PackageVersion($key) has no PackageVersionInfo.');
      }
    }

    _packageChecked++;
    if (_packageChecked % 200 == 0) {
      _logger.info('  .. $_packageChecked done (${p.name})');
    }
  }

  Future _checkVersions() async {
    _logger.info('Scanning PackageVersions...');
    await for (PackageVersion pv in _db.query<PackageVersion>().run()) {
      _checkPackageVersion(pv);
    }

    _packages
        .where((package) => !_packagesWithVersion.contains(package))
        .forEach((package) {
      _problems.add('Package ($package) has no version.');
    });
    _packagesWithVersion
        .where((package) => !_packages.contains(package))
        .forEach((package) {
      _problems.add('Package ($package) is missing.');
    });
  }

  void _checkPackageVersion(PackageVersion pv) {
    _packagesWithVersion.add(pv.package);

    if (pv.uploader == null) {
      _problems
          .add('PackageVersion(${pv.qualifiedVersionKey}) has no uploader.');
    }

    _versionChecked++;
    if (_versionChecked % 5000 == 0) {
      _logger.info('  .. $_versionChecked done (${pv.qualifiedVersionKey})');
    }
  }
}
