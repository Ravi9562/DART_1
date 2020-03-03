// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

import 'urls.dart';

const pubDartlangOrgEmail = 'pub@dartlang.org';
final _emailRegExp = RegExp(r'^\S+@\w+(\.\w+)+$');
final _nameEmailRegExp = RegExp(r'^(.*)<(.+@.+)>$');
final _defaultFrom = EmailAddress(
  'Dart package site admin',
  pubDartlangOrgEmail,
);

/// Represents a parsed email address.
class EmailAddress {
  final String name;
  final String email;

  EmailAddress(this.name, this.email);

  factory EmailAddress.parse(String value) {
    value = value.trim();
    String name = value;
    String email;

    final match = _nameEmailRegExp.matchAsPrefix(value);
    if (match != null) {
      name = match.group(1).trim();
      email = match.group(2).trim();
    } else if (value.contains('@')) {
      final List<String> parts = value.split(' ');
      for (int i = 0; i < parts.length; i++) {
        if (isValidEmail(parts[i])) {
          email = parts[i];
          parts.removeAt(i);
          name = parts.join(' ').trim();
          break;
        }
      }
    }
    if (name != null && name.isEmpty) {
      name = null;
    }
    if (!isValidEmail(email)) {
      email = null;
    }
    return EmailAddress(name, email);
  }

  bool get isEmpty => name == null && email == null;

  @override
  String toString() {
    if (isEmpty) return null;
    if (email == null) return name;
    if (name == null) return email;
    return '$name <$email>';
  }
}

/// Minimal accepted format for an email.
///
/// This function only disallows the most obvious non-email strings.
/// It still allows strings that aren't legal email  addresses.
bool isValidEmail(String email) {
  if (email == null) return false;
  if (email.length < 5) return false;
  if (email.contains('..')) return false;
  return _emailRegExp.hasMatch(email);
}

/// Represents an email message the site will send.
class EmailMessage {
  final EmailAddress from;
  final List<EmailAddress> recipients;
  final String subject;
  final String bodyText;

  EmailMessage(this.from, this.recipients, this.subject, String bodyText)
      : bodyText = reflowBodyText(bodyText);
}

/// Parses the body text and splits the [input] paragraphs to [lineLength]
/// character long lines.
String reflowBodyText(String input, {int lineLength = 72}) {
  Iterable<String> reflowLine(String line) sync* {
    if (line.isEmpty) {
      yield line;
      return;
    }
    while (line.length > lineLength) {
      int firstSpace = line.lastIndexOf(' ', lineLength);
      if (firstSpace < 20) {
        firstSpace = line.indexOf(' ', lineLength);
      }
      if (firstSpace != -1) {
        yield line.substring(0, firstSpace);
        line = line.substring(firstSpace).trim();
      } else {
        yield line;
        return;
      }
    }
    if (line.isNotEmpty) {
      yield line;
    }
  }

  return input.split('\n').expand(reflowLine).join('\n');
}

/// Creates the [EmailMessage] that we be sent on new package upload.
EmailMessage createPackageUploadedEmail({
  @required String packageName,
  @required String packageVersion,
  @required String uploaderEmail,
  @required List<EmailAddress> authorizedUploaders,
}) {
  final url =
      pkgPageUrl(packageName, version: packageVersion, includeHost: true);
  final subject = 'Package uploaded: $packageName $packageVersion';
  final bodyText = '''Dear package maintainer,  

$uploaderEmail has published a new version ($packageVersion) of the $packageName package to the Dart package site ($primaryHost).

For details, go to $url

If you have any concerns about this package, file an issue at https://github.com/dart-lang/pub-dev/issues

Thanks for your contributions to the Dart community!

With appreciation, the Dart package site admin
''';

  return EmailMessage(_defaultFrom, authorizedUploaders, subject, bodyText);
}

/// Creates the [EmailMessage] that will be sent to users about new invitations
/// they need to confirm.
EmailMessage createInviteEmail({
  @required String invitedEmail,
  @required String subject,
  @required String inviteText,
  @required String consentUrl,
}) {
  final bodyText = '''Dear Dart developer,

$inviteText

To accept this invitation, visit the following URL:
$consentUrl

If you don’t want to accept it, simply ignore this email.

If you have any concerns about this invitation, file an issue at https://github.com/dart-lang/pub-dev/issues

Thanks for your contributions to the Dart community!

With appreciation, the Dart package site admin
''';
  return EmailMessage(
      _defaultFrom, [EmailAddress(null, invitedEmail)], subject, bodyText);
}
