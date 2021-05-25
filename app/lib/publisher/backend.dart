// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:client_data/account_api.dart' as account_api;
import 'package:client_data/publisher_api.dart' as api;
import 'package:gcloud/service_scope.dart' as ss;
import 'package:logging/logging.dart';

import '../account/backend.dart';
import '../account/consent_backend.dart';
import '../audit/models.dart';
import '../shared/datastore.dart';
import '../shared/email.dart';
import '../shared/exceptions.dart';
import '../shared/redis_cache.dart' show cache, EntryPurgeExt;
import 'domain_verifier.dart' show domainVerifier;

import 'models.dart';

final _logger = Logger('pub.publisher.backend');

/// Sanity check to limit publisherId length.
const maxPublisherIdLength = 64;

/// Sets the publisher backend service.
void registerPublisherBackend(PublisherBackend backend) =>
    ss.register(#_publisherBackend, backend);

/// The active publisher backend service.
PublisherBackend get publisherBackend =>
    ss.lookup(#_publisherBackend) as PublisherBackend;

/// Represents the backend for the publisher handling and related utilities.
class PublisherBackend {
  final DatastoreDB _db;

  PublisherBackend(this._db);

  /// Loads a publisher (or returns null if it does not exists).
  Future<Publisher> getPublisher(String publisherId) async {
    checkPublisherIdParam(publisherId);
    final pKey = _db.emptyKey.append(Publisher, id: publisherId);
    return await _db.lookupValue<Publisher>(pKey, orElse: () => null);
  }

  /// List publishers (in no specific order, it will be listed by their
  /// `publisherId` alphabetically).
  Future<PublisherPage> listPublishers() async {
    return cache.allPublishersPage().get(() async {
      final sw = Stopwatch()..start();
      final query = _db.query<Publisher>();
      final publishers = await query
          .run()
          .map((p) => PublisherSummary(
                publisherId: p.publisherId,
                created: p.created,
              ))
          .toList();
      sw.stop();
      if (sw.elapsed.inSeconds > 10) {
        // When this is triggered, we should split the single list of publishers
        // to pages and adjust the uses of this method:
        // - sitemap-2.txt
        // - /publishers page
        _logger.shout('Querying all publishers takes more than 10 seconds.');
      }
      return PublisherPage(publishers: publishers);
    });
  }

  /// List all publishers where the [userId] is a member.
  Future<PublisherPage> listPublishersForUser(String userId) async {
    return cache.publisherPage(userId).get(() async {
      final query = _db.query<PublisherMember>()..filter('userId =', userId);
      final members = await query.run().toList();
      final publisherKeys = members.map((pm) => pm.publisherKey).toList();
      if (publisherKeys.length > 100) {
        // When this is triggered, we should split the single list of publishers
        // to pages and adjust the uses of this method:
        // - list of publishers on package admin page
        // - /my-publishers page
        // - search using this for query parameters
        _logger.shout('A user has more than 100 publishers.');
      }
      final publishers = await _db.lookup<Publisher>(publisherKeys);
      publishers.sort((a, b) => a.publisherId.compareTo(b.publisherId));
      return PublisherPage(
        publishers: publishers
            .map((p) => PublisherSummary(
                  publisherId: p.publisherId,
                  created: p.created,
                ))
            .toList(),
      );
    });
  }

  /// Loads the [PublisherMember] instance for [userId] (or returns null if it does not exists).
  Future<PublisherMember> getPublisherMember(
      String publisherId, String userId) async {
    checkPublisherIdParam(publisherId);
    ArgumentError.checkNotNull(userId, 'userId');
    final mKey = _db.emptyKey
        .append(Publisher, id: publisherId)
        .append(PublisherMember, id: userId);
    return await _db.lookupValue<PublisherMember>(mKey, orElse: () => null);
  }

  /// Whether the User [userId] has admin permissions on the publisher.
  Future<bool> isMemberAdmin(String publisherId, String userId) async {
    checkPublisherIdParam(publisherId);
    ArgumentError.checkNotNull(publisherId, 'publisherId');
    if (userId == null) return false;
    final member = await getPublisherMember(publisherId, userId);
    if (member == null) return false;
    return member.role == PublisherMemberRole.admin;
  }

  /// Create publisher.
  Future<api.PublisherInfo> createPublisher(
    String publisherId,
    api.CreatePublisherRequest body,
  ) async {
    checkPublisherIdParam(publisherId);
    final user = await requireAuthenticatedUser();
    // Sanity check that domains are:
    //  - lowercase (because we want that in pub.dev)
    //  - consist of a-z, 0-9 and dashes
    // We do not care if they end in dash, as such domains can't be verified.
    InvalidInputException.checkMatchPattern(
      publisherId,
      'publisherId',
      RegExp(r'^([a-z0-9-]{1,63}\.)+[a-z0-9-]{1,63}$'),
    );
    InvalidInputException.checkStringLength(
      publisherId,
      'publisherId',
      maximum: maxPublisherIdLength, // Some upper limit for sanity.
    );
    InvalidInputException.checkNotNull(body.accessToken, 'accessToken');
    InvalidInputException.checkStringLength(
      body.accessToken,
      'accessToken',
      minimum: 1,
      maximum: 4096,
    );
    await accountBackend.verifyAccessTokenOwnership(body.accessToken, user);

    // Verify ownership of domain.
    final isOwner = await domainVerifier.verifyDomainOwnership(
      publisherId,
      body.accessToken,
    );
    if (!isOwner) {
      throw AuthorizationException.userIsNotDomainOwner(publisherId);
    }

    // Create the publisher
    final now = DateTime.now().toUtc();
    await withRetryTransaction(_db, (tx) async {
      final key = _db.emptyKey.append(Publisher, id: publisherId);
      final p = await tx.lookupValue<Publisher>(key, orElse: () => null);
      if (p != null) {
        // Check that publisher is the same as what we would create.
        if (p.created.isBefore(now.subtract(Duration(minutes: 10))) ||
            p.updated.isBefore(now.subtract(Duration(minutes: 10))) ||
            p.contactEmail != user.email ||
            p.description != '' ||
            p.websiteUrl != _publisherWebsite(publisherId)) {
          throw ConflictException.publisherAlreadyExists(publisherId);
        }
        // Avoid creating the same publisher again, this end-point is idempotent
        // if we just do nothing here.
        return;
      }

      // Create publisher
      tx.queueMutations(inserts: [
        Publisher()
          ..parentKey = _db.emptyKey
          ..id = publisherId
          ..created = now
          ..description = ''
          ..contactEmail = user.email
          ..updated = now
          ..websiteUrl = _publisherWebsite(publisherId)
          ..isAbandoned = false,
        PublisherMember()
          ..parentKey = _db.emptyKey.append(Publisher, id: publisherId)
          ..id = user.userId
          ..userId = user.userId
          ..created = now
          ..updated = now
          ..role = PublisherMemberRole.admin,
        AuditLogRecord.publisherCreated(
          user: user,
          publisherId: publisherId,
        ),
      ]);
    });
    await purgeAccountCache(userId: user.userId);
    await cache.allPublishersPage().purge();

    // Return publisher as it was created
    final key = _db.emptyKey.append(Publisher, id: publisherId);
    final p = await _db.lookupValue<Publisher>(key);
    return _asPublisherInfo(p);
  }

  /// Gets the publisher data
  Future<api.PublisherInfo> getPublisherInfo(String publisherId) async {
    checkPublisherIdParam(publisherId);
    final p = await getPublisher(publisherId);
    if (p == null) {
      throw NotFoundException('Publisher $publisherId does not exists.');
    }
    return _asPublisherInfo(p);
  }

  /// Updates the publisher data.
  ///
  /// Handles: `PUT /api/publishers/<publisherId>`
  Future<api.PublisherInfo> updatePublisher(
      String publisherId, api.UpdatePublisherRequest update) async {
    checkPublisherIdParam(publisherId);
    if (update.description != null) {
      // limit length, if not null
      InvalidInputException.checkStringLength(
        update.description,
        'description',
        maximum: 4096,
      );
    }
    final user = await requireAuthenticatedUser();
    await requirePublisherAdmin(publisherId, user.userId);
    final p = await withRetryTransaction(_db, (tx) async {
      final key = _db.emptyKey.append(Publisher, id: publisherId);
      final p = await tx.lookupValue<Publisher>(key);

      // If websiteUrl has changed, check that it's under the [publisherId] domain.
      if (update.websiteUrl != null && p.websiteUrl != update.websiteUrl) {
        final parsedUrl = Uri.tryParse(update.websiteUrl);
        final isValid = parsedUrl != null && parsedUrl.isAbsolute;
        InvalidInputException.check(isValid, 'Not a valid URL.');
        InvalidInputException.checkAnyOf(
            parsedUrl.scheme, 'scheme', ['http', 'https']);

        InvalidInputException.check(parsedUrl.toString() == update.websiteUrl,
            'The parsed URL does not match its original form.');
      }

      // If contactEmail has changed, check that it's one of the admin's, and
      // if it matches an admin, set it directly, otherwise send an invite.
      if (update.contactEmail != null &&
          update.contactEmail != p.contactEmail) {
        InvalidInputException.checkStringLength(update.contactEmail, 'email',
            maximum: 4096);
        InvalidInputException.check(isValidEmail(update.contactEmail),
            'Invalid email: `${update.contactEmail}`');

        bool contactEmailMatchedAdmin = false;

        final usersByEmail =
            await accountBackend.lookupUsersByEmail(update.contactEmail);
        if (usersByEmail.isNotEmpty) {
          for (final user in usersByEmail) {
            if (await isMemberAdmin(publisherId, user.userId)) {
              contactEmailMatchedAdmin = true;
              p.contactEmail = update.contactEmail;
              break;
            }
          }

          if (!contactEmailMatchedAdmin) {
            InvalidInputException.check(
              user.email == update.contactEmail,
              'The contact email is a registered user, but not member of the publisher.',
            );
          }
        }

        if (!contactEmailMatchedAdmin) {
          await consentBackend.invitePublisherContact(
            publisherId: publisherId,
            contactEmail: update.contactEmail,
          );
        }
      }

      p.description = update.description ?? p.description;
      p.websiteUrl = update.websiteUrl ?? p.websiteUrl;
      p.updated = DateTime.now().toUtc();

      tx.insert(p);
      tx.insert(AuditLogRecord.publisherUpdated(
        user: user,
        publisherId: publisherId,
      ));
      return p;
    });

    await purgePublisherCache(publisherId: publisherId);
    return _asPublisherInfo(p);
  }

  /// Updates the contact email field of the publisher using a verified e-mail.
  Future updateContactWithVerifiedEmail(
      String publisherId, String contactEmail) async {
    checkPublisherIdParam(publisherId);
    final activeUser = await requireAuthenticatedUser();
    InvalidInputException.check(
        isValidEmail(contactEmail), 'Invalid email: `$contactEmail`');

    await withRetryTransaction(_db, (tx) async {
      final key = _db.emptyKey.append(Publisher, id: publisherId);
      final p = await tx.lookupValue<Publisher>(key);
      p.contactEmail = contactEmail;
      p.updated = DateTime.now().toUtc();
      tx.insert(p);
      tx.insert(AuditLogRecord.publisherContactInviteAccepted(
        user: activeUser,
        publisherId: publisherId,
        contactEmail: contactEmail,
      ));
    });
  }

  /// Invites a user to become a publisher admin.
  Future<account_api.InviteStatus> invitePublisherMember(
      String publisherId, api.InviteMemberRequest invite) async {
    checkPublisherIdParam(publisherId);
    final activeUser = await requireAuthenticatedUser();
    final p = await requirePublisherAdmin(publisherId, activeUser.userId);
    InvalidInputException.checkNotNull(invite.email, 'email');
    InvalidInputException.checkStringLength(invite.email, 'email',
        maximum: 4096);
    InvalidInputException.check(
        isValidEmail(invite.email), 'Invalid email: `${invite.email}`');

    final usersByEmail = await accountBackend.lookupUsersByEmail(invite.email);
    if (usersByEmail.isNotEmpty) {
      final maybeMembers = await _db.lookup<PublisherMember>(usersByEmail
          .map((u) => p.key.append(PublisherMember, id: u.userId))
          .toList());
      for (final m in maybeMembers) {
        if (m == null) continue;
        final email = await accountBackend.getEmailOfUserId(m.userId);
        InvalidInputException.check(
            email != invite.email, 'User is already a member.');
      }
    }

    return await consentBackend.invitePublisherMember(
      publisherId: p.publisherId,
      invitedUserEmail: invite.email,
    );
  }

  /// List the members of a publishers.
  Future<List<api.PublisherMember>> listPublisherMembers(
    String publisherId,
  ) async {
    checkPublisherIdParam(publisherId);
    final key = _db.emptyKey.append(Publisher, id: publisherId);
    // TODO: add caching
    final query = _db.query<PublisherMember>(ancestorKey: key);
    final members = <api.PublisherMember>[];
    await for (final pm in query.run()) {
      members.add(await _asPublisherMember(pm));
    }
    return members;
  }

  /// List the members of a publishers
  ///
  /// Handles: `GET /api/publishers/<publisherId>/members`
  Future<api.PublisherMembers> handleListPublisherMembers(
    String publisherId,
  ) async {
    checkPublisherIdParam(publisherId);
    final user = await requireAuthenticatedUser();
    await requirePublisherAdmin(publisherId, user.userId);
    return api.PublisherMembers(
      members: await listPublisherMembers(publisherId),
    );
  }

  /// The list of email addresses of the members with admin roles. The list
  /// should be used to notify admins on upload events.
  Future<List<String>> getAdminMemberEmails(String publisherId) async {
    checkPublisherIdParam(publisherId);
    final key = _db.emptyKey.append(Publisher, id: publisherId);
    final query = _db.query<PublisherMember>(ancestorKey: key);
    final userIds = await query.run().map((m) => m.userId).toList();
    return await accountBackend.getEmailsOfUserIds(userIds);
  }

  /// Returns the membership info of a user.
  Future<api.PublisherMember> publisherMemberInfo(
      String publisherId, String userId) async {
    checkPublisherIdParam(publisherId);
    final user = await requireAuthenticatedUser();
    final p = await requirePublisherAdmin(publisherId, user.userId);
    final key = p.key.append(PublisherMember, id: userId);
    final pm = await _db.lookupValue<PublisherMember>(key, orElse: () => null);
    if (pm == null) {
      throw NotFoundException.resource('member: $userId');
    }
    return await _asPublisherMember(pm);
  }

  /// Updates the membership info of a user.
  Future<api.PublisherMember> updatePublisherMember(
    String publisherId,
    String userId,
    api.UpdatePublisherMemberRequest update,
  ) async {
    checkPublisherIdParam(publisherId);
    final user = await requireAuthenticatedUser();
    final p = await requirePublisherAdmin(publisherId, user.userId);
    final key = p.key.append(PublisherMember, id: userId);
    final pm = await _db.lookupValue<PublisherMember>(key, orElse: () => null);
    if (pm == null) {
      throw NotFoundException.resource('member: $userId');
    }
    if (update.role != null && update.role != pm.role) {
      // user is not allowed to update their own role
      if (userId == user.userId) {
        throw ConflictException.cantUpdateOwnRole();
      }
      // role needs to be from the allowed set of values
      InvalidInputException.checkAnyOf(
          update.role, 'role', PublisherMemberRole.values);
      await withRetryTransaction(_db, (tx) async {
        final current = await tx.lookupValue<PublisherMember>(key);
        // fall back to current role if role is not updated
        current.role = update.role ?? current.role;
        current.updated = DateTime.now().toUtc();
        tx.insert(current);
      });
    }
    final updated = await _db.lookupValue<PublisherMember>(key);
    await purgePublisherCache(publisherId: publisherId);
    await purgeAccountCache(userId: userId);
    return await _asPublisherMember(updated);
  }

  /// Deletes a publisher's member.
  Future<void> deletePublisherMember(String publisherId, String userId) async {
    checkPublisherIdParam(publisherId);
    final user = await requireAuthenticatedUser();
    final p = await requirePublisherAdmin(publisherId, user.userId);
    if (userId == user.userId) {
      throw ConflictException.cantUpdateSelf();
    }

    final key = p.key.append(PublisherMember, id: userId);
    final pm = await _db.lookupValue<PublisherMember>(key, orElse: () => null);
    if (pm != null) {
      final memberUser = await accountBackend.lookupUserById(userId);
      final auditLogRecord = AuditLogRecord.publisherMemberRemoved(
        publisherId: publisherId,
        activeUser: user,
        memberToRemove: memberUser,
      );
      await _db.commit(inserts: [auditLogRecord], deletes: [pm.key]);
    }
    await purgePublisherCache(publisherId: publisherId);
    await purgeAccountCache(userId: userId);
  }

  /// A callback from consent backend, when a consent is granted.
  /// Note: this will be retried when transaction fails due race conditions.
  Future<void> inviteConsentGranted(String publisherId, String userId) async {
    checkPublisherIdParam(publisherId);
    final user = await accountBackend.lookupUserById(userId);
    await withRetryTransaction(_db, (tx) async {
      final key = _db.emptyKey
          .append(Publisher, id: publisherId)
          .append(PublisherMember, id: userId);
      final member =
          await tx.lookupValue<PublisherMember>(key, orElse: () => null);
      if (member != null) return;
      final now = DateTime.now().toUtc();
      tx.queueMutations(inserts: [
        PublisherMember()
          ..parentKey = key.parent
          ..id = userId
          ..userId = userId
          ..created = now
          ..updated = now
          ..role = PublisherMemberRole.admin,
        AuditLogRecord.publisherMemberInviteAccepted(
          user: user,
          publisherId: publisherId,
        ),
      ]);
    });
    await purgePublisherCache(publisherId: publisherId);
  }

  Future<api.PublisherMember> _asPublisherMember(PublisherMember pm) async {
    return api.PublisherMember(
      userId: pm.userId,
      role: pm.role,
      email: await accountBackend.getEmailOfUserId(pm.userId),
    );
  }
}

api.PublisherInfo _asPublisherInfo(Publisher p) => api.PublisherInfo(
      description: p.description,
      websiteUrl: p.websiteUrl,
      contactEmail: p.contactEmail,
    );

/// Loads [publisherId], returns its [Publisher] instance, and also checks if
/// [userId] is an admin of the publisher.
///
/// Throws AuthenticationException if the user is provided.
/// Throws AuthorizationException if the user is not an admin for the publisher.
Future<Publisher> requirePublisherAdmin(
    String publisherId, String userId) async {
  ArgumentError.checkNotNull(userId, 'userId');
  final p = await publisherBackend.getPublisher(publisherId);
  if (p == null) {
    throw NotFoundException('Publisher $publisherId does not exists.');
  }

  final member = await publisherBackend._db.lookupValue<PublisherMember>(
      p.key.append(PublisherMember, id: userId),
      orElse: () => null);

  if (member == null || member.role != PublisherMemberRole.admin) {
    _logger.info(
        'Unauthorized access of Publisher($publisherId) from User($userId).');
    throw AuthorizationException.userIsNotAdminForPublisher(publisherId);
  }
  return p;
}

/// Purge [cache] entries for given [publisherId].
Future purgePublisherCache({String publisherId}) async {
  await Future.wait([
    if (publisherId != null)
      cache.uiPublisherPackagesPage(publisherId).purgeAndRepeat(),
    cache.uiPublisherListPage().purge(),
  ]);
}

String _publisherWebsite(String domain) => 'https://$domain/';

/// Verify that the [publisherId] parameter looks as acceptable input.
void checkPublisherIdParam(String publisherId) {
  InvalidInputException.checkNotNull(publisherId, 'package');
  InvalidInputException.check(
      publisherId.trim() == publisherId, 'Invalid publisherId.');
  InvalidInputException.check(
      publisherId.contains('.'), 'Invalid publisherId.');
  InvalidInputException.checkStringLength(publisherId, 'publisherId',
      minimum: 3, maximum: 64);
}
