// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:gcloud/service_scope.dart' as ss;
import 'package:googleapis/youtube/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:pub_dev/shared/cached_value.dart';
import 'package:retry/retry.dart';

import '../secret/backend.dart';

final _logger = Logger('youtube.backend');

/// The playlist ID for the Package of the Week channel.
const powPlaylistId = 'PLjxrf2q8roU1quF6ny8oFHJ2gBdrYN_AK';

/// Sets the Youtube backend service.
void registerYoutubeBackend(YoutubeBackend backend) =>
    ss.register(#_youtubeBackend, backend);

/// The active Youtube backend service.
YoutubeBackend get youtubeBackend =>
    ss.lookup(#_youtubeBackend) as YoutubeBackend;

/// Represents the backend for the Youtube handling and related utilities.
class YoutubeBackend {
  final _packageOfWeekVideoList = CachedValue(
    name: 'pkg-of-week-video-list',
    interval: Duration(hours: 6),
    maxAge: Duration(hours: 24),
    timeout: Duration(hours: 13),
    updateFn: _PkgOfWeekVideoFetcher().fetchVideoList,
  );

  /// Starts the initial and schedules the periodic updates.
  Future<void> start() async {
    await _packageOfWeekVideoList.start();
  }

  /// Sets the list of PoW videos to a fixed value.
  @visibleForTesting
  void setPackageOfWeekVideos(List<PkgOfWeekVideo> videos) {
    // ignore: invalid_use_of_visible_for_testing_member
    _packageOfWeekVideoList.setValue(videos);
  }

  /// Returns a randomized selection from the list of videos.
  /// - The first item will be always kept as the first selected.
  /// - The second item will be selected from items #1-#3. (from the last month)
  /// - The rest of the items selection will be selected randomly.
  /// - Random seed changes hourly.
  List<PkgOfWeekVideo> getTopPackageOfWeekVideos({
    int count = 4,
    math.Random? random,
  }) {
    if (!_packageOfWeekVideoList.isAvailable) {
      return const <PkgOfWeekVideo>[];
    }
    final now = DateTime.now().toUtc();
    random ??= math.Random(
        now.year * 1000 + now.month * 100 + now.day * 10 + now.hour);
    final selectable =
        List<PkgOfWeekVideo>.from(_packageOfWeekVideoList.value!);
    final selected = <PkgOfWeekVideo>[];
    while (selected.length < count && selectable.isNotEmpty) {
      if (selected.isEmpty) {
        selected.add(selectable.removeAt(0));
      } else if (selected.length == 1) {
        final s =
            selectable.removeAt(random.nextInt(math.min(3, selectable.length)));
        selected.add(s);
      } else {
        selected.add(selectable.removeAt(random.nextInt(selectable.length)));
      }
    }
    return selected;
  }

  /// Cancels periodic updates.
  Future<void> close() async {
    await _packageOfWeekVideoList.close();
  }
}

class _PkgOfWeekVideoFetcher {
  final _retryOptions = RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(minutes: 1),
    maxDelay: Duration(minutes: 5),
  );

  Future<List<PkgOfWeekVideo>> fetchVideoList() async {
    return _retryOptions.retry(
      _fetchVideoList,
      retryIf: (e) => !e.toString().toLowerCase().contains('exceeded'),
    );
  }

  Future<List<PkgOfWeekVideo>> _fetchVideoList() async {
    final apiKey = Platform.environment['YOUTUBE_API_KEY'] ??
        await secretBackend.lookup(SecretKey.youtubeApiKey);
    if (apiKey == null || apiKey.isEmpty) return <PkgOfWeekVideo>[];

    final apiClient = clientViaApiKey(apiKey);
    final youtube = YouTubeApi(apiClient);

    try {
      final videos = <PkgOfWeekVideo>[];
      final videoIds = <String>{};
      int pageIndex = 0;
      String? nextPageToken;
      for (var check = true; check && videos.length < 50;) {
        final rs = await youtube.playlistItems.list(
          ['snippet', 'contentDetails'],
          playlistId: powPlaylistId,
        );
        for (final i in rs.items!) {
          final video = PkgOfWeekVideo(
            videoId: i.contentDetails!.videoId!,
            title: i.snippet!.title!,
            description:
                (i.snippet?.description ?? '').trim().split('\n').first,
            thumbnailUrl: i.snippet!.thumbnails!.high!.url!,
          );
          if (videoIds.add(video.videoId)) {
            videos.add(video);
          } else {
            _logger.warning(
                'Duplicate videoId "${video.videoId}" on page $pageIndex.');
          }
        }
        // next page
        nextPageToken = rs.nextPageToken;
        check = nextPageToken != null && nextPageToken.isNotEmpty;
        pageIndex++;
      }
      return videos;
    } finally {
      apiClient.close();
    }
  }
}

class PkgOfWeekVideo {
  final String videoId;
  final String title;
  final String description;
  final String thumbnailUrl;

  PkgOfWeekVideo({
    required this.videoId,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
  });

  String get videoUrl => Uri(
        scheme: 'https',
        host: 'youtube.com',
        path: '/watch',
        queryParameters: {
          'v': videoId,
          'list': powPlaylistId,
        },
      ).toString();
}
