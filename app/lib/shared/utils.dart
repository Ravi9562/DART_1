// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_dartlang_org.utils;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart' as semver;

final Logger _logger = new Logger('pub.utils');

Future<T> withTempDirectory<T>(Future<T> func(Directory dir),
    {String prefix: 'dart-tempdir'}) {
  return Directory.systemTemp.createTemp(prefix).then((Directory dir) {
    return func(dir).whenComplete(() {
      return dir.delete(recursive: true);
    });
  });
}

Future<List<String>> listTarball(String path) async {
  final args = ['--exclude=*/*/*', '-tzf', path];
  final result = await Process.run('tar', args);
  if (result.exitCode != 0) {
    _logger.warning('The "tar $args" command failed:\n'
        'with exit code: ${result.exitCode}\n'
        'stdout: ${result.stdout}\n'
        'stderr: ${result.stderr}');
    throw 'Failed to list tarball contents.';
  }

  return result.stdout.split('\n').where((part) => part != '').toList();
}

Future<String> readTarballFile(String path, String name) async {
  final result = await Process.run(
    'tar',
    ['-O', '-xzf', path, name],
    stdoutEncoding: new Utf8Codec(allowMalformed: true),
  );
  if (result.exitCode != 0) throw 'Failed to read tarball contents.';

  return result.stdout;
}

String canonicalizeVersion(String version) {
  // NOTE: This is a hack because [semver.Version.parse] does not remove
  // leading zeros for integer fields.
  final v = new semver.Version.parse(version);
  final pre = v.preRelease != null && v.preRelease.isNotEmpty
      ? v.preRelease.join('.')
      : null;
  final build =
      v.build != null && v.build.isNotEmpty ? v.build.join('.') : null;

  final canonicalVersion =
      new semver.Version(v.major, v.minor, v.patch, pre: pre, build: build);

  if (v != canonicalVersion) {
    throw new StateError(
        'This should never happen: Canonicalization of versions is wrong.');
  }
  return canonicalVersion.toString();
}

/// Compares two versions according to the semantic versioning specification.
///
/// If [pubSorted] is `true` then pub's priorization ordering is used, which
/// will rank pre-release versions lower than stable versions (e.g. it will
/// order "0.9.0-dev.1 < 0.8.0").  Otherwise it will use semantic version
/// sorting (e.g. it will order "0.8.0 < 0.9.0-dev.1").
int compareSemanticVersionsDesc(
    semver.Version a, semver.Version b, bool decreasing, pubSorted) {
  if (pubSorted) {
    if (decreasing) {
      return semver.Version.prioritize(b, a);
    } else {
      return semver.Version.prioritize(a, b);
    }
  } else {
    if (decreasing) {
      return b.compareTo(a);
    } else {
      return a.compareTo(b);
    }
  }
}

/// Returns true if [b] is considered newer than [a].
///
/// If [pubSorted] is `true` then pub's priorization ordering is used, which
/// will rank pre-release versions lower than stable versions (e.g. it will
/// order "0.9.0-dev.1 < 0.8.0").  Otherwise it will use semantic version
/// sorting (e.g. it will order "0.8.0 < 0.9.0-dev.1").
bool isNewer(semver.Version a, semver.Version b, {bool pubSorted: true}) =>
    compareSemanticVersionsDesc(a, b, false, pubSorted) < 0;

final RegExp _identifierExpr = new RegExp(r'^[a-zA-Z0-9_]+$');
final RegExp _startsWithLetterOrUnderscore = new RegExp(r'^[a-zA-Z_]');
const List<String> _reservedWords = const <String>[
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with'
];

/// Sanity checks if the user would upload a package with a modified pub client
/// that skips these verifications.
/// TODO: share code to use the same validations as in
/// https://github.com/dart-lang/pub/blob/master/lib/src/validator/name.dart#L52
void validatePackageName(String name) {
  if (!_identifierExpr.hasMatch(name)) {
    throw new Exception(
        'Package name may only contain letters, numbers, and underscores.');
  }
  if (!_startsWithLetterOrUnderscore.hasMatch(name)) {
    throw new Exception('Package name must begin with a letter or underscore.');
  }
  if (_reservedWords.contains(name.toLowerCase())) {
    throw new Exception('Package name must not be a reserved word in Dart.');
  }
}
