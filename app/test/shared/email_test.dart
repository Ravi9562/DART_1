// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub_dartlang_org/shared/email.dart';

void main() {
  group('EmailAddress.parse', () {
    void validateParse(String input, String name, String email) {
      final parsed = new EmailAddress.parse(input);
      expect(parsed.name, name);
      expect(parsed.email, email);
    }

    test('empty', () {
      validateParse('', null, null);
    });

    test('John Doe', () {
      validateParse('John Doe', 'John Doe', null);
      validateParse('<John Doe>', '<John Doe>', null);
      validateParse('John <Doe>', 'John <Doe>', null);
      validateParse('<John> <Doe>', '<John> <Doe>', null);
    });

    test('John Doe <email>', () {
      validateParse('John Doe <john.doe@example.com>', 'John Doe',
          'john.doe@example.com');
    });

    test('John Doe inline email', () {
      validateParse(
          'John Doe john.doe@example.com', 'John Doe', 'john.doe@example.com');
      validateParse(
          'John john.doe@example.com Doe', 'John Doe', 'john.doe@example.com');
    });

    test('email only', () {
      validateParse('john.doe@example.com', null, 'john.doe@example.com');
      validateParse('<john.doe@example.com>', null, 'john.doe@example.com');
    });
  });

  group('EmailAddress format', () {
    test('empty', () {
      expect(new EmailAddress(null, null).toString(), null);
    });

    test('name only', () {
      expect(new EmailAddress('John Doe', null).toString(), 'John Doe');
    });

    test('email only', () {
      expect(new EmailAddress(null, 'john.doe@example.com').toString(),
          'john.doe@example.com');
    });

    test('composite', () {
      expect(new EmailAddress('John Doe', 'john.doe@example.com').toString(),
          'John Doe <john.doe@example.com>');
    });
  });

  group('reflowByteText', () {
    test('small text', () {
      expect(reflowBodyText(''), '');
      expect(reflowBodyText('a'), 'a');
      expect(reflowBodyText('a b c'), 'a b c');
      expect(reflowBodyText('a\nb\nc'), 'a\nb\nc');
    });

    test('empty lines', () {
      expect(reflowBodyText('line 1\n\nline 2\n\n\nline 3'),
          'line 1\n\nline 2\n\n\nline 3');
    });

    test('long line', () {
      expect(
          reflowBodyText(
              'line 0\nabc def ghi jkl mno pqr stu vwx yz0 123 456 789 abc def ghi jkl '
              'mno pqr stu vwx yz0 123 456 789 abc def ghi jkl mno pqr stu vwx '
              'yz0 123 456 789 abc def ghi jkl mno pqr stu vwx yz0 123 456 789\nline 2'),
          'line 0\n'
          'abc def ghi jkl mno pqr stu vwx yz0 123 456 789 abc def ghi jkl mno pqr\n'
          'stu vwx yz0 123 456 789 abc def ghi jkl mno pqr stu vwx yz0 123 456 789\n'
          'abc def ghi jkl mno pqr stu vwx yz0 123 456 789\n'
          'line 2');
    });

    test('long word', () {
      expect(
          reflowBodyText(
              'sdhfbdskhfgbdfhgbdgdfgkdhsfvdkhfvddhjfbgkdhjfbgsdkhjfbgksdjhfgbdskfhgb'),
          'sdhfbdskhfgbdfhgbdgdfgkdhsfvdkhfvddhjfbgkdhjfbgsdkhjfbgksdjhfgbdskfhgb');
      expect(
          reflowBodyText(
              'abcdefg sdhfbdskhfgbdfhgbdgdfgkdhsfvdkhfvddhjfbgkdhjfbgsdkhjfbgksdjhfgbdskfhgb'),
          'abcdefg sdhfbdskhfgbdfhgbdgdfgkdhsfvdkhfvddhjfbgkdhjfbgsdkhjfbgksdjhfgbdskfhgb');
      expect(
          reflowBodyText(
              'abcdefg sdhfbdskhfgbdfhgbdgdfgkdhsfvdkhfvddhjfbgkdhjfbgsdkhjfbgksdjhfgbdskfhgb abcdefg'),
          'abcdefg sdhfbdskhfgbdfhgbdgdfgkdhsfvdkhfvddhjfbgkdhjfbgsdkhjfbgksdjhfgbdskfhgb\n'
          'abcdefg');
    });
  });

  group('Package uploaded emails', () {
    test('2 uploaders, 4 authors, 1 common, 1 without e-mail', () {
      final message = createPackageUploadedEmail(
        packageName: 'pkg_foo',
        packageVersion: '1.0.0',
        uploaderEmail: 'uploader@example.com',
        authorizedUploaders: [
          new EmailAddress('Joe', 'joe@example.com'),
          new EmailAddress(null, 'uploader@example.com')
        ],
        authors: [
          new EmailAddress('Jane', 'jane@example.com'),
          new EmailAddress(null, 'uploader@example.com'),
          new EmailAddress(null, 'team@example.com'),
          new EmailAddress('And many others', null),
        ],
      );
      expect(message.from.toString(), 'Pub Site Admin <pub@dartlang.org>');
      expect(message.recipients.map((e) => e.toString()).toList(), [
        'Joe <joe@example.com>',
        'uploader@example.com',
      ]);
      expect(message.subject, 'Package upload on pub: pkg_foo 1.0.0');
      expect(
          message.bodyText,
          'Dear package maintainer,\n'
          '\n'
          'uploader@example.com uploaded a new version of package pkg_foo: 1.0.0\n'
          '\n'
          'If you think this is a mistake or fraud, contact us at pub@dartlang.org\n'
          '\n'
          'Pub Site Admin\n');
    });
  });
}
