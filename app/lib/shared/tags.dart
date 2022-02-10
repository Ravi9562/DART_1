// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Tag prefixes that are allowed.
///
/// Whether a tag is assigned by pub-administrator, package owner, or derived
/// by pana it must have a prefix listed here. Otherwise, it should be ignore
/// or an error should be returned to the caller.
const allowedTagPrefixes = [
  'is:',
  'platform:',
  'runtime:',
  'sdk:',
  'show:',
];

/// Collection of package-related tags.
abstract class PackageTags {
  /// Package is marked discontinued | unlisted | legacy.
  static const String isHidden = 'is:hidden';

  /// Package is shown, regardless of its hidden status.
  static const String showHidden = 'show:hidden';

  /// Package is marked discontinued.
  static const String isDiscontinued = 'is:discontinued';

  /// Package is shown, regardless of its discontinued status.
  static const String showDiscontinued = 'show:discontinued';

  /// Package is marked unlisted.
  static const String isUnlisted = 'is:unlisted';

  /// Package is shown, regardless of its unlisted status.
  static const String showUnlisted = 'show:unlisted';

  /// The first version of the package was published less than 30 days ago.
  static const String isRecent = 'is:recent';

  /// Package is marked with Flutter Favorite.
  static const String isFlutterFavorite = 'is:flutter-favorite';

  /// The `publisher:<publisherId>` tag.
  static String publisherTag(String publisherId) => 'publisher:$publisherId';
}

/// Collection of version-related tags.
abstract class PackageVersionTags {
  /// PackageVersion supports only legacy (Dart 1) SDK.
  static const String isLegacy = 'is:legacy';

  /// Package is shown, regardless of its legacy status.
  static const String showLegacy = 'show:legacy';

  /// The PackageVersion is null-safe.
  ///
  /// See definition at `_NullSafetyViolationFinder` in
  /// https://github.com/dart-lang/pana/blob/master/lib/src/tag_detection.dart
  static const String isNullSafe = 'is:null-safe';
}

/// Collection of SDK tags (with prefix and value).
abstract class SdkTag {
  static const String sdkDart = 'sdk:${SdkTagValue.dart}';
  static const String sdkFlutter = 'sdk:${SdkTagValue.flutter}';
}

/// Collection of SDK tag values.
abstract class SdkTagValue {
  static const String dart = 'dart';
  static const String flutter = 'flutter';
  static const String any = 'any';

  static bool isAny(String? value) => value == null || value == any;
  static bool isNotAny(String? value) => !isAny(value);
  static bool isValidSdk(String value) => value == dart || value == flutter;
}

/// Collection of Dart SDK runtime tags (with prefix and value).
abstract class DartSdkTag {
  static const String runtimeNativeAot = 'runtime:${DartSdkRuntime.nativeAot}';
  static const String runtimeNativeJit = 'runtime:${DartSdkRuntime.nativeJit}';
  static const String runtimeWeb = 'runtime:${DartSdkRuntime.web}';
}

/// Collection of Dart SDK runtime values.
abstract class DartSdkRuntime {
  static const String nativeAot = 'native-aot';
  static const String nativeJit = 'native-jit';
  static const String web = 'web';
}

/// Collection of Flutter SDK platform tags (with prefix and value).
abstract class FlutterSdkTag {
  static const String platformAndroid =
      'platform:${FlutterSdkPlatform.android}';
  static const String platformIos = 'platform:${FlutterSdkPlatform.ios}';
  static const String platformMacos = 'platform:${FlutterSdkPlatform.macos}';
  static const String platformLinux = 'platform:${FlutterSdkPlatform.linux}';
  static const String platformWeb = 'platform:${FlutterSdkPlatform.web}';
  static const String platformWindows =
      'platform:${FlutterSdkPlatform.windows}';
}

/// Collection of Flutter SDK platform values.
abstract class FlutterSdkPlatform {
  static const String android = 'android';
  static const String ios = 'ios';
  static const String linux = 'linux';
  static const String macos = 'macos';
  static const String web = 'web';
  static const String windows = 'windows';
}
