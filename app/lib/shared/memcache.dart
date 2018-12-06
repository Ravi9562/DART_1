// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:memcache/memcache.dart';

import 'versions.dart';

const Duration indexUiPageExpiration = const Duration(minutes: 10);
const Duration packageJsonExpiration = const Duration(minutes: 10);
const Duration packageUiPageExpiration = const Duration(minutes: 10);
const Duration dartdocEntryExpiration = const Duration(hours: 24);
const Duration dartdocFileInfoExpiration = const Duration(minutes: 60);
const Duration scoreCardDataExpiration = const Duration(minutes: 60);
const Duration searchServiceResultExpiration = const Duration(minutes: 10);
const Duration _memcacheRequestTimeout = const Duration(seconds: 5);

const String indexUiPageKey = 'v2_pub_index';
const String packageJsonPrefix = 'v2_package_json_';
const String packageUiPagePrefix = 'v2_package_ui_';
const String dartdocEntryPrefix = 'dartdoc_entry_';
const String dartdocFileInfoPrefix = 'dartdoc_fileinfo_';
const String scoreCardDataPrefix = 'scorecard_';
const String searchServiceResultPrefix = 'search_service_result_';

// Appengine's memcache has a content limit of 1MB (1024 * 124).
// Keeping it under that limit in order to offset char coding or other payloads.
const _contentLimit = 1000 * 1000;

class SimpleMemcache2 {
  final Logger _logger;
  final Memcache _memcache;
  final String _prefix;
  final Duration _expiration;

  SimpleMemcache2(this._logger, this._memcache, this._prefix, this._expiration);

  String _key(String key) => '$runtimeVersion/$_prefix$key';

  Future<String> getText(String key) async {
    try {
      return (await _memcache.get(_key(key)).timeout(_memcacheRequestTimeout))
          as String;
    } catch (e, st) {
      _logger.severe('Error accessing memcache:', e, st);
    }
    _logger.fine('Couldn\'t find memcache entry for $key');
    return null;
  }

  Future setText(String key, String content) async {
    if (content == null) return;
    if (content.length >= _contentLimit) {
      _logger.info('Content too large for memcache entry for $key '
          '(length: ${content.length}, limit: $_contentLimit).');
      return;
    }
    try {
      await _memcache
          .set(_key(key), content, expiration: _expiration)
          .timeout(_memcacheRequestTimeout);
    } catch (e, st) {
      _logger.warning('Couldn\'t set memcache entry for $key', e, st);
    }
  }

  Future<List<int>> getBytes(String key) async {
    try {
      return (await _memcache
          .get(_key(key), asBinary: true)
          .timeout(_memcacheRequestTimeout)) as List<int>;
    } catch (e, st) {
      _logger.severe('Error accessing memcache:', e, st);
    }
    _logger.fine('Couldn\'t find memcache entry for $key');
    return null;
  }

  Future setBytes(String key, List<int> content) async {
    if (content == null) return;
    if (content.length >= _contentLimit) {
      _logger.info('Content too large for memcache entry for $key '
          '(length: ${content.length}, limit: $_contentLimit).');
      return;
    }
    try {
      await _memcache
          .set(_key(key), content, expiration: _expiration)
          .timeout(_memcacheRequestTimeout);
    } catch (e, st) {
      _logger.warning('Couldn\'t set memcache entry for $key', e, st);
    }
  }

  Future invalidate(String key) async {
    _logger.info('Invalidating memcache key: $key');
    try {
      await _memcache.remove(_key(key)).timeout(_memcacheRequestTimeout);
    } catch (e, st) {
      _logger.warning('Couldn\'t remove memcache entry for $key', e, st);
    }
  }
}
