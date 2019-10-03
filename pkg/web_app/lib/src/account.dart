// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';
import 'dart:js';

import 'package:client_data/account_api.dart';
import 'package:client_data/package_api.dart';
import 'package:client_data/publisher_api.dart';
import 'package:http/http.dart' as http;
import 'package:markdown/markdown.dart' as markdown;

import '_authenticated_client.dart';
import '_dom_helper.dart';
import 'google_auth_js.dart';
import 'google_js.dart';
import 'page_data.dart';
import 'pubapi.client.dart';

bool _initialized = false;
GoogleUser _currentUser;

/// Returns whether the user is currently signed-in.
bool get isSignedIn => _initialized && _currentUser != null;

/// Returns the currently signed-in user or null.
GoogleUser get currentUser => _currentUser;

PubApiClient _client;
http.Client _httpClient;
final _pkgAdminWidget = _PkgAdminWidget();
final _publisherAdminWidget = _PublisherAdminWidget();
final _createPublisherWidget = _CreatePublisherWidget();
final _consentWidget = _ConsentWidget();

/// The pub API client to use with account credentials.
PubApiClient get client {
  if (_client == null) {
    _httpClient ??=
        getAuthenticatedClient(currentUser?.getAuthResponse(true)?.id_token);
    final uri = Uri.parse(window.location.href);
    _client = PubApiClient(uri.resolve('/').toString(), client: _httpClient);
  }
  return _client;
}

void setupAccount() {
  // Initialization hook that will run after the auth library is loaded and
  // initialized. Method name is passed in as request parameter when loading
  // the auth library.
  context['pubAuthInit'] = () {
    final clientId = document
        .querySelector('meta[name="google-signin-client_id"]')
        .attributes['content'];
    if (clientId == null) return;
    load('auth2', allowInterop(() {
      init(JsObject.jsify({'client_id': clientId}))
          .then(allowInterop((_) => _init()));
    }));
  };
}

void _init() {
  _initialized = true;
  document
      .getElementById('-account-login')
      ?.onClick
      ?.listen((_) => getAuthInstance().signIn());
  document
      .getElementById('-account-logout')
      ?.onClick
      ?.listen((_) => getAuthInstance().signOut());
  _pkgAdminWidget.init();
  _createPublisherWidget.init();
  _publisherAdminWidget.init();
  _consentWidget.init();
  _updateUser(getAuthInstance()?.currentUser?.get());
  getAuthInstance().currentUser.listen(allowInterop(_updateUser));
}

Future _updateUser(GoogleUser user) async {
  if (_initialized && !getAuthInstance().isSignedIn.get()) {
    user = null;
  }
  if (user?.getId() == null) {
    user = null;
  }
  _currentUser = user;

  // reset credentials used in the HTTP Client
  _httpClient?.close();
  _httpClient = null;
  _client = null;

  // update or delete session
  if (user == null) {
    final st1 = ClientSessionStatus.fromBytes(await client.invalidateSession());
    if (st1.changed) {
      final st2 = ClientSessionStatus.fromBytes(
        await client.invalidateSession(),
      );
      // Only reload if signing out again, didn't change anything.
      // If signing out a second time changes something, then clearly sign-out
      // isn't clearing the cookie and session correctly. We should not reload
      // to avoid degrading into a reload loop.
      if (!st2.changed) {
        window.location.reload();
        return;
      }
    }
  } else {
    final st1 = ClientSessionStatus.fromBytes(await client.updateSession(
      ClientSessionData(
        imageUrl: user.getBasicProfile().getImageUrl(),
      ),
    ));
    if (st1.changed) {
      final st2 = ClientSessionStatus.fromBytes(await client.updateSession(
        ClientSessionData(
          imageUrl: user.getBasicProfile().getImageUrl(),
        ),
      ));
      // If creating the session a second time changed anything then maybe the
      // client has disabled cookies. We should NOT reload to avoid degrading
      // into an infinite reload loop. We could show a message, but we have no
      // way of preventing this message from poping up on all pages, so it's
      // probably best to ignore this case.
      if (!st2.changed) {
        window.location.reload();
        return;
      } else {
        print('Sign-in will not work without session cookies');
      }
    }
  }

  _updateUi();
}

void _updateUi() {
  if (isSignedIn) {
    print('user: ${currentUser.getBasicProfile().getEmail()}');
  } else {
    print('No active user');
  }
  _pkgAdminWidget.update();
  _createPublisherWidget.update();
  _publisherAdminWidget.update();
  _consentWidget.update();
}

/// Active on /packages/<package>/admin page.
class _PkgAdminWidget {
  Element _toggleDiscontinuedButton;
  InputElement _setPublisherInput;
  Element _setPublisherButton;

  void init() {
    if (!pageData.isPackagePage) return;
    _toggleDiscontinuedButton =
        document.getElementById('-admin-is-discontinued-toggle');
    _setPublisherInput =
        document.getElementById('-admin-set-publisher-input') as InputElement;
    _setPublisherButton =
        document.getElementById('-admin-set-publisher-button');
    if (isActive) {
      _toggleDiscontinuedButton.onClick.listen((_) => _toogleDiscontinued());
      _setPublisherButton?.onClick?.listen((_) => _setPublisher());
    }
    update();
  }

  Future _toogleDiscontinued() async {
    final confirmed = await modalConfirm(
        'Are you sure you want change the "discontinued" status of the package?');
    if (!confirmed) return;

    final options =
        PkgOptions(isDiscontinued: !pageData.pkgData.isDiscontinued);
    await _rpc(() async {
      await client.setPackageOptions(pageData.pkgData.package, options);
      window.location.reload();
    });
  }

  Future _setPublisher() async {
    final publisherId = _setPublisherInput.value.trim();
    if (publisherId.isEmpty) {
      await modalMessage(
        'Input validation',
        'Please specify a publisher.',
      );
      return;
    }
    final confirmed = await modalConfirm(
        'Are you sure you want to transfer the package to publisher <code>$publisherId</code>?');
    if (!confirmed) return;

    final payload = PackagePublisherInfo(publisherId: publisherId);
    await _rpc(() async {
      await client.setPackagePublisher(pageData.pkgData.package, payload);
      window.location.reload();
    });
  }

  void update() {
    // nothing to do
  }

  bool get isActive =>
      _toggleDiscontinuedButton != null &&
      _setPublisherButton != null &&
      _setPublisherInput != null;
}

/// Active on the /create-publisher page.
class _CreatePublisherWidget {
  Element _publisherIdInput;
  Element _createButton;

  void init() {
    _publisherIdInput = document.getElementById('-publisher-id');
    _createButton = document.getElementById('-admin-create-publisher');
    if (isActive) {
      update();
      _createButton.onClick.listen((_) {
        final publisherId = (_publisherIdInput as InputElement).value.trim();
        _triggerCreate(publisherId);
      });
    }
  }

  void update() {
    if (!isActive) return;
  }

  void _triggerCreate(String publisherId) async {
    if (publisherId.isEmpty || !publisherId.contains('.')) {
      await modalMessage(
          'Input validation', 'Please use a domain name as publisher id.');
      return;
    }
    final confirmed = await modalConfirm(
        'Are you sure you want to create publisher for <code>$publisherId</code>?');
    if (!confirmed) return;

    GoogleUser currentUser = getAuthInstance()?.currentUser?.get();
    final extraScope = 'https://www.googleapis.com/auth/webmasters.readonly';

    if (!currentUser.hasGrantedScopes(extraScope)) {
      // We don't have the extract scope, so let's ask for it
      currentUser = await promiseAsFuture(currentUser.grant(GrantOptions(
        scope: extraScope,
      )));
    }
    final payload = CreatePublisherRequest(
      accessToken: currentUser.getAuthResponse(true).access_token,
    );
    await _rpc(() async {
      await client.createPublisher(publisherId, payload);
      window.location.pathname = '/publishers/$publisherId';
    });
  }

  bool get isActive => _publisherIdInput != null && _createButton != null;
}

/// Active on the /publishers/<publisherId>/admin page.
class _PublisherAdminWidget {
  Element _updateButton;
  TextAreaElement _descriptionTextArea;
  InputElement _websiteUrlInput;
  InputElement _contactEmailInput;
  InputElement _inviteMemberInput;
  Element _inviteMemberButton;
  Future<PublisherMembers> membersFuture;

  void init() {
    if (!pageData.isPublisherPage) return;
    _updateButton = document.getElementById('-publisher-update-button');
    _descriptionTextArea =
        document.getElementById('-publisher-description') as TextAreaElement;
    _websiteUrlInput =
        document.getElementById('-publisher-website-url') as InputElement;
    _contactEmailInput =
        document.getElementById('-publisher-contact-email') as InputElement;
    _inviteMemberInput =
        document.getElementById('-admin-invite-member-input') as InputElement;
    _inviteMemberButton =
        document.getElementById('-admin-invite-member-button');
    if (isActive) {
      _updateButton.onClick.listen((_) => _updatePublisher());
      _inviteMemberButton.onClick.listen((_) => _inviteMember());
    }
    update();
  }

  Future _updatePublisher() async {
    final payload = UpdatePublisherRequest(
      description: _descriptionTextArea.value,
      websiteUrl: _websiteUrlInput.value,
      contactEmail: _contactEmailInput.value,
    );
    await _rpc(() async {
      await client.updatePublisher(pageData.publisher.publisherId, payload);
      window.location.pathname =
          '/publishers/${pageData.publisher.publisherId}';
    });
  }

  Future _inviteMember() async {
    final email = _inviteMemberInput.value.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      await modalMessage('Input validation', 'Please specify a valid e-mail.');
      return;
    }
    final confirmed = await modalConfirm(
        'Are you sure you want to invite <code>$email</code> '
        'as an administrator member to this publisher?');
    if (!confirmed) return;

    final payload = InviteMemberRequest(email: email);
    await _rpc(() async {
      await client.invitePublisherMember(
          pageData.publisher.publisherId, payload);
    });
  }

  Future _removeMember(PublisherMember pm) async {
    final confirmed = await modalConfirm(
        'Are you sure you want to remove <code>${pm.email}</code> from this publisher?');
    if (!confirmed) return;

    await _rpc(() async {
      await client.removePublisherMember(
          pageData.publisher.publisherId, pm.userId);
      window.location.reload();
    });
  }

  void update() {
    if (!isActive) return;
    // only trigger the loading of the members list once
    if (membersFuture == null) {
      final publisherId = pageData.publisher.publisherId;
      membersFuture = client.listPublisherMembers(publisherId);
      membersFuture.then((pms) async {
        final table = Element.table()
          ..children = pms.members.map((pm) {
            final button = Element.tag('button')
              ..className = 'pub-button'
              ..text = 'Remove member'
              ..onClick.listen((_) => _removeMember(pm));

            return Element.tr()
              ..children = [
                Element.td()..text = pm.email,
                Element.td()..children = [button],
              ];
          }).toList();

        document.getElementById('-admin-members-loading').replaceWith(table);
      });
    }
  }

  bool get isActive =>
      _descriptionTextArea != null &&
      _websiteUrlInput != null &&
      _contactEmailInput != null &&
      _updateButton != null &&
      _inviteMemberInput != null &&
      _inviteMemberButton != null;
}

class _ConsentWidget {
  Element _title;
  Element _content;
  Element _buttons;
  Future<Consent> _consentFuture;
  bool _loaded = false;

  void init() {
    if (!pageData.isConsentPage) return;
    _title = document.getElementById('-admin-consent-title');
    _content = document.getElementById('-admin-consent-content');
    _buttons = document.getElementById('-admin-consent-buttons');
    document
        .getElementById('-admin-consent-accept-button')
        .onClick
        .listen((_) => _accept());
    document
        .getElementById('-admin-consent-reject-button')
        .onClick
        .listen((_) => _reject());
  }

  void update() {
    if (!pageData.isConsentPage) return;

    updateDisplay(_buttons, _loaded);

    if (isSignedIn && _consentFuture == null) {
      _consentFuture = client.consentInfo(pageData.consentId);
      _consentFuture.then((consent) {
        _title.innerText = consent.titleText;
        _content.replaceWith(Element.div()
          ..children = [
            Element.div()..innerHtml = consent.descriptionHtml,
          ]);
        _loaded = true;
        update();
      }).catchError((e) {
        String text = 'Error: $e';
        if (e is RequestException) {
          if (e.status == 404) {
            text = 'Consent request `${pageData.consentId}` has expired.';
          } else {
            text = (e.bodyAsJson()['message'] as String) ?? text;
          }
        }
        _content.replaceWith(Element.div()..text = text);
      });
    }
  }

  void _updateButtons(bool granted) {
    final text = granted ? 'Consent accepted.' : 'Consent rejected.';
    _buttons.replaceWith(Element.p()..text = text);
  }

  Future _accept() async {
    final confirmed = await modalConfirm('Are you sure you want to accept?');
    if (!confirmed) return;

    await _rpc(() async {
      final rs = await client.resolveConsent(
          pageData.consentId, ConsentResult(granted: true));
      _updateButtons(rs.granted);
    });
  }

  Future _reject() async {
    final confirmed = await modalConfirm('Are you sure you want to reject?');
    if (!confirmed) return;

    await _rpc(() async {
      final rs = await client.resolveConsent(
          pageData.consentId, ConsentResult(granted: false));
      _updateButtons(rs.granted);
    });
  }

  bool get isActive => _content != null && _buttons != null;
}

Future<R> _rpc<R>(Future<R> fn()) async {
  // Disable input and button Elements that are not disabled at the moment.
  final inputs = document
      .querySelectorAll('input')
      .cast<InputElement>()
      .where((e) => !e.disabled)
      .toList();
  final buttons = document
      .querySelectorAll('button.pub-button')
      .cast<ButtonElement>()
      .where((e) => !e.disabled)
      .toList();

  buttons.forEach((e) => e.disabled = true);
  inputs.forEach((e) => e.disabled = true);
  try {
    return await fn();
  } on RequestException catch (e) {
    final message = markdown
        .markdownToHtml(_requestExceptionMessage(e) ?? 'Unexpected error: $e');
    await modalMessage('Error', message);
    rethrow;
  } catch (e) {
    final message = markdown.markdownToHtml('Unexpected error: $e');
    await modalMessage('Error', message);
    rethrow;
  } finally {
    buttons.forEach((e) => e.disabled = false);
    inputs.forEach((e) => e.disabled = false);
  }
}

String _requestExceptionMessage(RequestException e) {
  try {
    final map = e.bodyAsJson();
    return (map['message'] as String) ?? (map['error'] as String);
  } on FormatException catch (_) {
    // ignore bad body
  }
  return null;
}
