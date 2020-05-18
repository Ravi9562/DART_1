// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:pub_dev/search/token_index.dart';

void main() {
  group('TokenIndex', () {
    test('No match', () {
      final TokenIndex index = TokenIndex()
        ..add('uri://http', 'http')
        ..add('uri://http_magic', 'http_magic');

      expect(index.search('xml'), {
        // no match for http
        // no match for http_magic
      });
    });

    test('Scoring exact and partial matches', () {
      final TokenIndex index = TokenIndex()
        ..add('uri://http', 'http')
        ..add('uri://http_magic', 'http_magic');
      expect(index.search('http'), {
        'uri://http': closeTo(0.993, 0.001),
        'uri://http_magic': closeTo(0.989, 0.001),
      });
    });

    test('CamelCase indexing', () {
      final String queueText = '.DoubleLinkedQueue()';
      final TokenIndex index = TokenIndex()
        ..add('queue', queueText)
        ..add('queue_lower', queueText.toLowerCase())
        ..add('unmodifiable', 'CustomUnmodifiableMapBase');
      expect(index.search('queue'), {
        'queue': closeTo(0.29, 0.01),
      });
      expect(index.search('unmodifiab'), {
        'unmodifiable': closeTo(0.47, 0.01),
      });
      expect(index.search('unmodifiable'), {
        'unmodifiable': closeTo(0.47, 0.01),
      });
    });

    test('Wierd cases: riak client', () {
      final TokenIndex index = TokenIndex()
        ..add('uri://cli', 'cli')
        ..add('uri://riak_client', 'riak_client')
        ..add('uri://teamspeak', 'teamspeak');

      expect(index.search('riak'), {
        'uri://riak_client': closeTo(0.99, 0.01),
      });

      expect(index.search('riak client'), {
        'uri://riak_client': closeTo(0.99, 0.01),
      });
    });

    test('Free up memory', () {
      final TokenIndex index = TokenIndex();
      expect(index.tokenCount, 0);
      index.add('url1', 'text');
      expect(index.tokenCount, 1);
      index.add('url2', 'another');
      expect(index.tokenCount, 2);
      index.remove('url2');
      expect(index.tokenCount, 1);
    });
  });

  group('TokenMatch', () {
    test('longer words', () {
      final index = TokenIndex(minLength: 2);
      final names = [
        'location',
        'geolocator',
        'firestore_helpers',
        'geolocation',
        'location_context',
        'amap_location',
        'flutter_location_picker',
        'flutter_amap_location',
        'location_picker',
        'background_location_updates',
      ];
      for (String name in names) {
        index.add(name, name);
      }
      final match = index.lookupTokens('location');
      // location should be the top value, everything else should be lower
      expect(match.tokenWeights, {
        'location': 1.0,
        'geolocation': closeTo(0.727, 0.001),
      });
    });

    test('short words: lookup for app', () {
      final index = TokenIndex(minLength: 2);
      index.add('app', 'app');
      index.add('apps', 'apps');
      final match = index.lookupTokens('app');
      expect(match.tokenWeights, {'app': 1.0, 'apps': 0.75});
    });
  });

  group('Score', () {
    Score score;
    setUp(() {
      score = Score({'a': 100.0, 'b': 30.0, 'c': 55.0});
    });

    test('remove low scores', () {
      expect(score.getValues(), {
        'a': 100.0,
        'b': 30.0,
        'c': 55.0,
      });
      expect(score.removeLowValues(fraction: 0.31).getValues(), {
        'a': 100.0,
        'c': 55.0,
      });
      expect(score.removeLowValues(minValue: 56.0).getValues(), {
        'a': 100.0,
      });
    });
  });
}
