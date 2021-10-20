// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../../../search/search_form.dart';
import '../../../../shared/tags.dart';
import '../../../dom/dom.dart' as d;
import '../../../request_context.dart';
import '../../../static_files.dart';
import '../../layout.dart';

/// Renders the package listing.
d.Node packageListingNode({
  required SearchForm searchForm,
  required d.Node? subSdkButtons,
  required d.Node listingInfo,
  required d.Node packageList,
  required d.Node? pagination,
}) {
  final innerContent = d.fragment([
    listingInfo,
    packageList,
    if (pagination != null) pagination,
    d.markdown('Check our help page for details on '
        '[search expressions](/help/search#query-expressions) and '
        '[result ranking](/help/search#ranking).'),
  ]);
  if (requestContext.showNewSearchUI) {
    return _searchFormContainer(
      searchForm: searchForm,
      innerContent: innerContent,
    );
  } else {
    return d.fragment([
      _searchControls(searchForm, subSdkButtons),
      d.div(classes: ['container'], child: innerContent),
    ]);
  }
}

d.Node _searchFormContainer({
  required SearchForm searchForm,
  required d.Node innerContent,
}) {
  return d.div(
    classes: ['container', 'search-form-container', 'experimental'],
    children: [
      d.div(
        classes: ['search-form'],
        children: [
          _filterSection(
            label: 'Platforms',
            isActive: true,
            children: [
              // TODO: add platform checkboxes
              d.span(text: '[placeholder]'),
            ],
          ),
          _filterSection(
            label: 'SDKs',
            children: [
              // TODO: add SDK checkboxes
              d.span(text: '[placeholder]'),
            ],
          ),
        ],
      ),
      d.div(
        classes: ['search-results'],
        child: innerContent,
      ),
    ],
  );
}

d.Node _filterSection({
  required String label,
  required Iterable<d.Node> children,
  bool isActive = false,
}) {
  return d.div(
    classes: ['search-form-section', 'foldable', if (isActive) '-active'],
    children: [
      d.h3(
        classes: ['search-form-section-header foldable-button'],
        children: [
          d.span(classes: ['search-form-section-header-label'], text: label),
          d.img(
            classes: ['foldable-icon'],
            src: staticUrls
                .getAssetUrl('/static/img/search-form-foldable-icon.svg'),
          ),
        ],
      ),
      d.div(
        classes: ['foldable-content'],
        children: children,
      ),
    ],
  );
}

d.Node _searchControls(SearchForm searchForm, d.Node? subSdkButtons) {
  final includeDiscontinued = searchForm.includeDiscontinued;
  final includeUnlisted = searchForm.includeUnlisted;
  final nullSafe = searchForm.nullSafe;
  final hasActiveAdvanced = includeDiscontinued || includeUnlisted || nullSafe;
  return d.div(
    classes: [
      'search-controls',
      if (hasActiveAdvanced) '-active',
    ],
    children: [
      d.div(
        classes: ['container'],
        child: d.div(
          classes: ['search-controls-primary'],
          children: [
            d.div(
              classes: ['search-controls-sdk', 'search-controls-tabs'],
              child: sdkTabsNode(searchForm: searchForm),
            ),
            d.div(
              classes: ['search-controls-sdk', 'search-controls-buttons'],
              children: [
                d.span(classes: ['search-controls-label'], text: 'SDK'),
                sdkTabsNode(searchForm: searchForm),
              ],
            ),
            d.div(
              classes: [
                'search-filters-btn',
                'search-filters-btn-wrapper',
                'search-controls-more',
              ],
              attributes: {'data-ga-click-event': 'toggle-advanced-search'},
              children: [
                d.text('Advanced '),
                d.img(
                  classes: ['search-controls-more-carot'],
                  src: staticUrls.getAssetUrl('/static/img/carot-up.svg'),
                ),
              ],
            ),
          ],
        ),
      ),
      if (subSdkButtons != null)
        d.div(
          classes: ['search-controls-subsdk'],
          child: d.div(
            classes: ['container'],
            children: [
              d.span(
                classes: ['search-controls-label'],
                text: _subSdkLabel(searchForm),
              ),
              d.div(
                classes: ['search-controls-buttons'],
                child: subSdkButtons,
              ),
            ],
          ),
        ),
      d.div(
        classes: ['search-controls-advanced'],
        child: d.div(
          classes: ['container'],
          child: d.div(
            classes: ['search-controls-advanced-block'],
            children: [
              _checkbox(
                id: '-search-unlisted-checkbox',
                label: 'Include unlisted packages',
                name: 'unlisted',
                checked: includeUnlisted,
              ),
              _checkbox(
                id: '-search-discontinued-checkbox',
                label: 'Include discontinued packages',
                name: 'discontinued',
                checked: includeDiscontinued,
              ),
              _checkbox(
                id: '-search-null-safe-checkbox',
                label: 'Supports null safety',
                name: 'null-safe',
                checked: nullSafe,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

d.Node _checkbox({
  required String id,
  required String label,
  required String name,
  required bool checked,
}) {
  return d.div(
    classes: ['search-controls-checkbox'],
    children: [
      d.input(
        type: 'checkbox',
        id: id,
        name: name,
        attributes: checked ? {'checked': 'checked'} : null,
      ),
      d.label(attributes: {'for': id}, text: label),
    ],
  );
}

String? _subSdkLabel(SearchForm sq) {
  if (sq.context.sdk == SdkTagValue.dart) {
    return 'Runtime';
  } else if (sq.context.sdk == SdkTagValue.flutter) {
    return 'Platform';
  } else {
    return null;
  }
}
