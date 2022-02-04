// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:_pub_shared/data/admin_api.dart' as api;
import 'package:_pub_shared/data/package_api.dart';
import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:convert/convert.dart';
import 'package:gcloud/service_scope.dart' as ss;
import 'package:gcloud/storage.dart';
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';
import 'package:pub_dev/audit/models.dart';
import 'package:pub_dev/shared/email.dart';
import 'package:pub_semver/pub_semver.dart';

import '../account/backend.dart';
import '../account/models.dart';
import '../dartdoc/backend.dart';
import '../job/model.dart';
import '../package/backend.dart'
    show
        TarballStorage,
        checkPackageVersionParams,
        packageBackend,
        purgePackageCache;
import '../package/models.dart';
import '../publisher/models.dart';
import '../scorecard/models.dart';
import '../shared/configuration.dart';
import '../shared/datastore.dart';
import '../shared/exceptions.dart';
import '../shared/tags.dart';
import '../tool/utils/dart_sdk_version.dart';

final _logger = Logger('pub.admin.backend');
final _continuationCodec = utf8.fuse(hex);

/// Sets the admin backend service.
void registerAdminBackend(AdminBackend backend) =>
    ss.register(#_adminBackend, backend);

/// The active admin backend service.
AdminBackend get adminBackend => ss.lookup(#_adminBackend) as AdminBackend;

/// Represents the backend for the admin handling and authentication.
class AdminBackend {
  final DatastoreDB _db;
  AdminBackend(this._db);

  /// Require that the incoming request is authorized by an administrator with
  /// the given [permission].
  Future<User> _requireAdminPermission(AdminPermission permission) async {
    ArgumentError.checkNotNull(permission, 'permission');

    final user = await requireAuthenticatedUser();
    final admin = activeConfiguration.admins!.firstWhereOrNull(
        (a) => a.oauthUserId == user.oauthUserId && a.email == user.email);
    if (admin == null || !admin.permissions.contains(permission)) {
      _logger.warning(
          'User (${user.userId} / ${user.email}) is trying to access unauthorized admin APIs.');
      throw AuthorizationException.userIsNotAdminForPubSite();
    }
    return user;
  }

  /// List users.
  ///
  ///
  Future<api.AdminListUsersResponse> listUsers({
    String? email,
    String? oauthUserId,
    String? continuationToken,
    int limit = 1000,
  }) async {
    InvalidInputException.checkRange(limit, 'limit', minimum: 1, maximum: 1000);
    await _requireAdminPermission(AdminPermission.listUsers);

    final query = _db.query<User>()..limit(limit);

    if (email != null) {
      InvalidInputException.checkNull(oauthUserId, '?ouid=');
      InvalidInputException.checkNull(continuationToken, '?ct=');
      query.filter('email =', email);
    } else if (oauthUserId != null) {
      InvalidInputException.checkNull(continuationToken, '?ct=');
      query.filter('oauthUserId =', oauthUserId);
    } else if (continuationToken != null) {
      String lastId;
      try {
        lastId = _continuationCodec.decode(continuationToken);
      } on FormatException catch (_) {
        throw InvalidInputException.continuationParseError();
      }
      InvalidInputException.checkNotNull(lastId, '?ct=');

      // NOTE: we should fix https://github.com/dart-lang/gcloud/issues/23
      //       and remove the toDatastoreKey conversion here.
      final key =
          _db.modelDB.toDatastoreKey(_db.emptyKey.append(User, id: lastId));
      query.filter('__key__ >', key);
      query.order('__key__');
    } else {
      query.order('__key__');
    }

    final users = await query.run().toList();
    // We may return a page with users less then a limit, but we always
    // set the continuation token to the correct value.
    final newContinuationToken = users.length < limit
        ? null
        : _continuationCodec.encode(users.last.userId);
    users.removeWhere((u) => u.isDeleted);

    return api.AdminListUsersResponse(
      users: users
          .map(
            (u) => api.AdminUserEntry(
              userId: u.userId,
              email: u.email,
              oauthUserId: u.oauthUserId,
            ),
          )
          .toList(),
      continuationToken: newContinuationToken,
    );
  }

  /// Removes user from the Datastore and updates the packages and other
  /// entities they may have controlled.
  Future<void> removeUser(String userId) async {
    final caller = await _requireAdminPermission(AdminPermission.removeUsers);
    final user = await accountBackend.lookupUserById(userId);
    if (user == null) return;
    if (user.isDeleted) return;

    _logger.info('${caller.userId} (${caller.email}) initiated the delete '
        'of ${user.userId} (${user.email})');

    // Package.uploaders
    final pool = Pool(10);
    final futures = <Future>[];
    final pkgQuery = _db.query<Package>()..filter('uploaders =', user.userId);
    await for (final p in pkgQuery.run()) {
      final f = pool
          .withResource(() => _removeUploaderFromPackage(p.key, user.userId));
      futures.add(f);
    }
    await Future.wait(futures);
    await pool.close();

    // PublisherMember
    // Publisher.contactEmail
    final memberQuery = _db.query<PublisherMember>()
      ..filter('userId =', user.userId);
    await for (final m in memberQuery.run()) {
      await _removeMember(user, m);
    }

    // Like
    await _removeAndDecrementLikes(user);

    // User
    // OAuthUserID
    // TODO: consider deleting User if there are no other references to it
    await _markUserDeleted(user);
  }

  // Remove like entities and decrement likes count on all packages liked by [user].
  Future<void> _removeAndDecrementLikes(User user) async {
    final pool = Pool(5);
    final futures = <Future>[];
    for (final like in await accountBackend.listPackageLikes(user)) {
      final f = pool.withResource(
          () => accountBackend.unlikePackage(user, like.package!));
      futures.add(f);
    }
    await Future.wait(futures);
    await pool.close();
  }

  Future<void> _removeUploaderFromPackage(Key pkgKey, String userId) async {
    await withRetryTransaction(_db, (tx) async {
      final p = await tx.lookupValue<Package>(pkgKey);
      p.removeUploader(userId);
      if (p.uploaders!.isEmpty) {
        p.isDiscontinued = true;
      }
      tx.insert(p);
    });
  }

  Future<void> _removeMember(User user, PublisherMember member) async {
    final seniorMember =
        await _remainingSeniorMember(member.publisherKey, member.userId!);
    await withRetryTransaction(_db, (tx) async {
      final p = await tx.lookupValue<Publisher>(member.publisherKey);
      if (seniorMember == null) {
        p.isAbandoned = true;
        p.contactEmail = null;
        // TODO: consider deleting Publisher if there are no other references to it
      } else if (p.contactEmail == user.email) {
        final seniorUser =
            await accountBackend.lookupUserById(seniorMember.userId!);
        p.contactEmail = seniorUser!.email;
      }
      tx.queueMutations(inserts: [p], deletes: [member.key]);
    });
    if (seniorMember == null) {
      // mark packages under the publisher discontinued
      final query = _db.query<Package>()
        ..filter('publisherId =', member.publisherId);
      final pool = Pool(4);
      final futures = <Future>[];
      await for (final package in query.run()) {
        if (package.isDiscontinued) continue;
        final f = pool.withResource(
          () => withRetryTransaction(_db, (tx) async {
            final p = await tx.lookupValue<Package>(package.key);
            p.isDiscontinued = true;
            tx.insert(p);
          }),
        );
        futures.add(f);
      }
      await Future.wait(futures);
      await pool.close();
    }
  }

  /// Returns the member of the publisher that (a) is not removed,
  /// (b) preferably is an admin, and (c) is member of the publisher for the
  /// longest time.
  ///
  /// If there are no more admins left, the "oldest" non-admin member is returned.
  Future<PublisherMember?> _remainingSeniorMember(
      Key publisherKey, String excludeUserId) async {
    final otherMembers = await _db
        .query<PublisherMember>(ancestorKey: publisherKey)
        .run()
        .where((m) => m.userId != excludeUserId)
        .toList();

    if (otherMembers.isEmpty) return null;

    // sort admins in the front, and on equal level sort by created time
    otherMembers.sort((a, b) {
      if (a.role == b.role) return a.created!.compareTo(b.created!);
      if (a.role == PublisherMemberRole.admin) return -1;
      if (b.role == PublisherMemberRole.admin) return 1;
      return a.created!.compareTo(b.created!);
    });

    return otherMembers.first;
  }

  Future<void> _markUserDeleted(User user) async {
    await withRetryTransaction(_db, (tx) async {
      final u = await tx.lookupValue<User>(user.key);
      final deleteKeys = <Key>[];
      if (user.oauthUserId != null) {
        final mappingKey =
            _db.emptyKey.append(OAuthUserID, id: user.oauthUserId);
        final mapping = (await tx.lookup<OAuthUserID>([mappingKey])).single;
        if (mapping != null) {
          deleteKeys.add(mappingKey);
        }
      }

      u
        ..oauthUserId = null
        ..created = null
        ..isDeleted = true;
      tx.queueMutations(inserts: [u], deletes: deleteKeys);
    });
  }

  /// Removes the package from the Datastore and updates other related
  /// entities. It is safe to call [removePackage] on an already removed
  /// package, as the call is idempotent.
  ///
  /// Creates a [ModeratedPackage] instance (if not already present) in
  /// Datastore representing the removed package. No new package with the same
  /// name can be published.
  Future<void> removePackage(String packageName) async {
    final caller = await _requireAdminPermission(AdminPermission.removePackage);

    _logger.info('${caller.userId} (${caller.email}) initiated the delete '
        'of package $packageName');

    final packageKey = _db.emptyKey.append(Package, id: packageName);
    final versions = (await _db
            .query<PackageVersion>(ancestorKey: packageKey)
            .run()
            .map((pv) => pv.version!)
            .toList())
        .toSet();

    await withRetryTransaction(_db, (tx) async {
      final package = await tx.lookupOrNull<Package>(packageKey);
      if (package == null) {
        _logger
            .info('Package $packageName not found. Removing related elements.');
        // Returning early makes sure we are not creating ghost `ModeratedPackage`
        // entities because of a typo.
        return;
      }
      tx.delete(packageKey);

      final moderatedPkgKey =
          _db.emptyKey.append(ModeratedPackage, id: packageName);
      final moderatedPkg =
          await _db.lookupOrNull<ModeratedPackage>(moderatedPkgKey);
      if (moderatedPkg == null) {
        // Refresh versions to make sure we are not missing a freshly uploaded one.
        versions.addAll(await tx
            .query<PackageVersion>(packageKey)
            .run()
            .map((pv) => pv.version!)
            .toList());

        tx.insert(ModeratedPackage()
          ..parentKey = _db.emptyKey
          ..id = packageName
          ..name = packageName
          ..moderated = clock.now().toUtc()
          ..versions = versions.toList()
          ..publisherId = package.publisherId
          ..uploaders = package.uploaders);

        _logger.info('Adding package to moderated packages ...');
      }
    });

    final pool = Pool(10);
    final futures = <Future>[];
    final storage = TarballStorage(storageService,
        storageService.bucket(activeConfiguration.packageBucketName!), '');
    versions.forEach((final v) {
      futures.add(pool.withResource(() => storage.remove(packageName, v)));
    });
    await Future.wait(futures);
    await pool.close();

    _logger.info('Removing package from dartdoc backend ...');
    await dartdocBackend.removeAll(packageName, concurrency: 32);

    _logger.info('Removing package from PackageVersion ...');
    await _db
        .deleteWithQuery(_db.query<PackageVersion>(ancestorKey: packageKey));

    _logger.info('Removing package from PackageVersionInfo ...');
    await _db.deleteWithQuery(
        _db.query<PackageVersionInfo>()..filter('package =', packageName));

    _logger.info('Removing package from PackageVersionAsset ...');
    await _db.deleteWithQuery(
        _db.query<PackageVersionAsset>()..filter('package =', packageName));

    _logger.info('Removing package from Jobs ...');
    await _db.deleteWithQuery(
        _db.query<Job>()..filter('packageName =', packageName));

    _logger.info('Removing package from ScoreCard ...');
    await _db.deleteWithQuery(
        _db.query<ScoreCard>()..filter('packageName =', packageName));

    _logger.info('Removing package from Like ...');
    await _db.deleteWithQuery(
        _db.query<Like>()..filter('packageName =', packageName));

    _logger.info('Package "$packageName" got successfully removed.');
    _logger.info(
        'NOTICE: Redis caches referencing the package will expire given time.');
  }

  /// Updates the options (e.g. retraction) of the specific package version and
  /// updates other related entities.
  /// It is safe to call [updateVersionOptions] on an version with the same
  /// options values (e.g. same retracted status), as the call is idempotent.
  Future<void> updateVersionOptions(
      String packageName, String version, VersionOptions options) async {
    checkPackageVersionParams(packageName, version);
    InvalidInputException.check(options.isRetracted != null,
        'Only updating "isRetracted" is implemented.');
    final caller =
        await _requireAdminPermission(AdminPermission.manageRetraction);

    if (options.isRetracted != null) {
      final isRetracted = options.isRetracted!;
      _logger.info(
          '${caller.userId} (${caller.email}) initiated the isRetracted status '
          'of package $packageName $version to be $isRetracted.');

      await withRetryTransaction(_db, (tx) async {
        final p = await tx.lookupOrNull<Package>(
            _db.emptyKey.append(Package, id: packageName));
        if (p == null) {
          throw NotFoundException.resource(packageName);
        }
        final pv = await tx.lookupOrNull<PackageVersion>(
            p.key.append(PackageVersion, id: version));
        if (pv == null) {
          throw NotFoundException.resource(version);
        }

        if (pv.isRetracted != isRetracted) {
          await packageBackend.doUpdateRetractedStatus(
              caller, tx, p, pv, isRetracted);
        }
      });
      await purgePackageCache(packageName);
    }
  }

  /// Removes the specific package version from the Datastore and updates other
  /// related entities. It is safe to call [removePackageVersion] on an already
  /// removed version, as the call is idempotent.
  Future<void> removePackageVersion(String packageName, String version) async {
    final caller = await _requireAdminPermission(AdminPermission.removePackage);

    _logger.info('${caller.userId} (${caller.email}) initiated the delete '
        'of package $packageName $version');

    final currentDartSdk = await getDartSdkVersion();
    await withRetryTransaction(_db, (tx) async {
      final packageKey = _db.emptyKey.append(Package, id: packageName);
      final package = await tx.lookupOrNull<Package>(packageKey);
      if (package == null) {
        throw Exception(
            'Package "$packageName" does not exists. Use full package removal without the version qualifier.');
      }

      final versionsQuery = tx.query<PackageVersion>(packageKey);
      final versions = await versionsQuery.run().toList();
      final versionNames = versions.map((v) => v.version).toList();
      if (versionNames.contains(version)) {
        tx.delete(packageKey.append(PackageVersion, id: version));
        package.versionCount--;
        package.updated = clock.now().toUtc();
      } else {
        print('Package $packageName does not have a version $version.');
      }

      if (versionNames.length == 1 && versionNames.single == version) {
        throw Exception(
            'Last version detected. Use full package removal without the version qualifier.');
      }

      if (package.mayAffectLatestVersions(Version.parse(version))) {
        package.updateLatestVersionReferences(
            versions.where((v) => v.version != version).toList(),
            dartSdkVersion: currentDartSdk.semanticVersion);
      }

      package.deletedVersions ??= <String>[];
      if (!package.deletedVersions!.contains(version)) {
        package.deletedVersions!.add(version);
      }

      tx.insert(package);
    });

    final bucket =
        storageService.bucket(activeConfiguration.packageBucketName!);
    final storage = TarballStorage(storageService, bucket, '');
    print('Removing GCS objects ...');
    await storage.remove(packageName, version);

    await dartdocBackend.removeAll(packageName, version: version);

    await _db.deleteWithQuery(
      _db.query<PackageVersionInfo>()..filter('package =', packageName),
      where: (PackageVersionInfo info) => info.version == version,
    );

    await _db.deleteWithQuery(
      _db.query<PackageVersionAsset>()..filter('package =', packageName),
      where: (PackageVersionAsset asset) => asset.version == version,
    );

    await _db.deleteWithQuery(
      _db.query<Job>()..filter('packageName =', packageName),
      where: (Job job) => job.packageVersion == version,
    );
    await purgePackageCache(packageName);
  }

  /// Handles GET '/api/admin/packages/<package>/assigned-tags'
  ///
  /// Note, this API end-point is intentioanlly locked down even if it doesn't
  /// return anything secret. This is because the /admin/ section is only
  /// intended to be exposed to administrators. Users can read the assigned-tags
  /// through API that returns list of package tags.
  Future<api.AssignedTags> handleGetAssignedTags(
    String packageName,
  ) async {
    checkPackageVersionParams(packageName);
    await _requireAdminPermission(AdminPermission.manageAssignedTags);
    final package = await packageBackend.lookupPackage(packageName);
    if (package == null) {
      throw NotFoundException.resource(packageName);
    }

    return api.AssignedTags(
      assignedTags: package.assignedTags!,
    );
  }

  /// Handles POST '/api/admin/packages/<package>/assigned-tags'
  Future<api.AssignedTags> handlePostAssignedTags(
    String packageName,
    api.PatchAssignedTags body,
  ) async {
    await _requireAdminPermission(AdminPermission.manageAssignedTags);

    InvalidInputException.check(
      body.assignedTagsAdded
          .every((tag) => allowedTagPrefixes.any(tag.startsWith)),
      'Only following tag-prefixes are allowed "${allowedTagPrefixes.join("\", ")}"',
    );
    InvalidInputException.check(
      body.assignedTagsAdded
          .toSet()
          .intersection(body.assignedTagsRemoved.toSet())
          .isEmpty,
      'assignedTagsAdded cannot contain tags also removed assignedTagsRemoved',
    );

    return await withRetryTransaction(_db, (tx) async {
      final package = await tx.lookupOrNull<Package>(_db.emptyKey.append(
        Package,
        id: packageName,
      ));

      if (package == null) {
        throw NotFoundException.resource(packageName);
      }

      if (package.assignedTags!.any(body.assignedTagsRemoved.contains) ||
          !body.assignedTagsAdded.every(package.assignedTags!.contains)) {
        package.assignedTags!
          ..removeWhere(body.assignedTagsRemoved.contains)
          ..addAll(body.assignedTagsAdded);
        package.updated = clock.now().toUtc();
        tx.insert(package);
      }

      return api.AssignedTags(
        assignedTags: package.assignedTags!,
      );
    });
  }

  /// Handles GET '/api/admin/packages/<package>/uploaders'
  ///
  /// Returns the list of uploaders for a package.
  Future<api.PackageUploaders> handleGetPackageUploaders(
    String packageName,
  ) async {
    checkPackageVersionParams(packageName);
    await _requireAdminPermission(AdminPermission.managePackageOwnership);
    final package = await packageBackend.lookupPackage(packageName);
    if (package == null) {
      throw NotFoundException.resource(packageName);
    }
    InvalidInputException.check(
        package.publisherId == null, 'Package must not be under a publisher.');

    final uploaders = <api.AdminUserEntry>[];
    for (final userId in package.uploaders!) {
      final email = await accountBackend.getEmailOfUserId(userId);
      uploaders.add(api.AdminUserEntry(userId: userId, email: email));
    }
    return api.PackageUploaders(uploaders: uploaders);
  }

  /// Handles PUT '/api/admin/packages/<package>/uploaders/<email>'
  ///
  /// Returns the list of uploaders for a package.
  Future<api.PackageUploaders> handleAddPackageUploader(
      String packageName, String email) async {
    checkPackageVersionParams(packageName);
    final adminUser =
        await _requireAdminPermission(AdminPermission.managePackageOwnership);
    final package = await packageBackend.lookupPackage(packageName);
    if (package == null) {
      throw NotFoundException.resource(packageName);
    }

    final uploaderEmail = email.toLowerCase();
    InvalidInputException.check(
        isValidEmail(uploaderEmail), 'Not a valid email: `$uploaderEmail`.');
    final uploaderUser =
        await accountBackend.lookupOrCreateUserByEmail(uploaderEmail);

    await withRetryTransaction(_db, (tx) async {
      final p = await tx.lookupValue<Package>(package.key);
      InvalidInputException.check(
          p.publisherId == null, 'Package must not be under a publisher.');
      if (p.uploaders!.contains(uploaderUser.userId)) {
        // do not throw if email is already added
        return;
      } else {
        p.uploaders!.add(uploaderUser.userId);
      }
      tx.insert(p);
      tx.insert(AuditLogRecord.uploaderAdded(
        activeUser: adminUser,
        package: packageName,
        uploaderUser: uploaderUser,
      ));
    });
    return await handleGetPackageUploaders(packageName);
  }

  /// Handles DELETE '/api/admin/packages/<package>/uploaders/<email>'
  ///
  /// Returns the list of uploaders for a package.
  Future<api.PackageUploaders> handleRemovePackageUploader(
      String packageName, String email) async {
    checkPackageVersionParams(packageName);
    final adminUser =
        await _requireAdminPermission(AdminPermission.managePackageOwnership);
    final package = await packageBackend.lookupPackage(packageName);
    if (package == null) {
      throw NotFoundException.resource(packageName);
    }

    final uploaderEmail = email.toLowerCase();
    InvalidInputException.check(
        isValidEmail(uploaderEmail), 'Not a valid email: `$uploaderEmail`.');
    final uploaderUsers =
        await accountBackend.lookupUsersByEmail(uploaderEmail);
    InvalidInputException.check(uploaderUsers.isNotEmpty,
        'No users found for email: `$uploaderEmail`.');

    await withRetryTransaction(_db, (tx) async {
      final p = await tx.lookupValue<Package>(package.key);
      InvalidInputException.check(
          p.publisherId == null, 'Package must not be under a publisher.');
      var removed = false;
      for (final uploaderUser in uploaderUsers) {
        final r = p.uploaders!.remove(uploaderUser.userId);
        if (r) {
          removed = true;
          tx.insert(AuditLogRecord.uploaderRemoved(
            activeUser: adminUser,
            package: packageName,
            uploaderUser: uploaderUser,
          ));
        }
      }
      if (removed) {
        if (p.uploaders!.isEmpty) {
          p.isDiscontinued = true;
          tx.insert(AuditLogRecord.packageOptionsUpdated(
            package: packageName,
            user: adminUser,
            options: ['discontinued'],
          ));
        }
        p.updated = clock.now().toUtc();
        tx.insert(p);
      }
    });
    return await handleGetPackageUploaders(packageName);
  }
}
