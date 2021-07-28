// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../shared/tags.dart' show SdkTagValue;

class SdkDict {
  final String topSdkPackages;
  final String searchPackagesLabel;
  final String libraryTypeLabel;

  const SdkDict({
    required this.topSdkPackages,
    required this.searchPackagesLabel,
    required this.libraryTypeLabel,
  });

  const SdkDict.any()
      : topSdkPackages = 'Top packages',
        searchPackagesLabel = 'Search packages',
        libraryTypeLabel = 'SDK library';

  const SdkDict.dart()
      : topSdkPackages = 'Top Dart packages',
        searchPackagesLabel = 'Search Dart packages',
        libraryTypeLabel = 'Dart SDK library';

  const SdkDict.flutter()
      : topSdkPackages = 'Top Flutter packages',
        searchPackagesLabel = 'Search Flutter packages',
        libraryTypeLabel = 'Flutter SDK library';
}

/// Returns the dictionary spec for [sdk].
SdkDict getSdkDict(String? sdk) {
  if (sdk == SdkTagValue.dart) {
    return SdkDict.dart();
  } else if (sdk == SdkTagValue.flutter) {
    return SdkDict.flutter();
  } else {
    return SdkDict.any();
  }
}

final defaultLandingBlurbHtml =
    '<p class="text">The official package repository for <a target="_blank" rel="noopener" href="https://dart.dev/">Dart</a> and '
    '<a target="_blank" rel="noopener" href="https://flutter.dev/">Flutter</a> apps.</p>';

class SortDict {
  final String id;
  final String label;
  final String tooltip;

  const SortDict({
    required this.id,
    required this.label,
    required this.tooltip,
  });
}

final _sortDicts = const <SortDict>[
  SortDict(
      id: 'listing_relevance',
      label: 'listing relevance',
      tooltip:
          'Packages are sorted by the combination of their overall score and '
          'their specificity to the selected platform.'),
  SortDict(
      id: 'search_relevance',
      label: 'search relevance',
      tooltip: 'Packages are sorted by the combination of the text match, '
          'their overall score and their specificity to the selected platform.'),
  SortDict(
      id: 'top',
      label: 'overall score',
      tooltip: 'Packages are sorted by the overall score.'),
  SortDict(
      id: 'updated',
      label: 'recently updated',
      tooltip: 'Packages are sorted by their updated time.'),
  SortDict(
      id: 'created',
      label: 'newest package',
      tooltip: 'Packages are sorted by their created time.'),
  SortDict(
      id: 'like',
      label: 'most likes',
      tooltip: 'Packages are sorted by like count.'),
  SortDict(
      id: 'points',
      label: 'most pub points',
      tooltip: 'Packages are sorted by pub points.'),
  SortDict(
      id: 'popularity',
      label: 'popularity',
      tooltip: 'Packages are sorted by their popularity score.'),
];

List<SortDict> getSortDicts(bool isSearch) {
  final removeId = isSearch ? 'listing_relevance' : 'search_relevance';
  return <SortDict>[
    ..._sortDicts.where((d) => d.id != removeId),
  ];
}
