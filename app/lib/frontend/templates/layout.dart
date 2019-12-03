// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:client_data/page_data.dart';
import 'package:meta/meta.dart';

import '../../account/backend.dart';
import '../../search/search_service.dart';
import '../../shared/configuration.dart';
import '../../shared/platform.dart' show KnownPlatforms;
import '../../shared/tags.dart';
import '../../shared/urls.dart' as urls;

import '../request_context.dart';
import '../static_files.dart';

import '_cache.dart';
import '_consts.dart';
import '_utils.dart';

enum PageType {
  error,
  account,
  landing,
  listing,
  package,
  publisher,
  standalone,
}

/// Renders the `views/layout.mustache` template.
String renderLayoutPage(
  PageType type,
  String contentHtml, {
  @required String title,
  String pageDescription,
  String faviconUrl,
  String canonicalUrl,
  String platform,
  String sdk,
  String publisherId,
  SearchQuery searchQuery,
  bool includeSurvey = true,
  bool noIndex = false,
  PageData pageData,
}) {
  final isRoot = type == PageType.landing && platform == null;
  final pageDataEncoded = pageData == null
      ? null
      : htmlAttrEscape.convert(pageDataJsonCodec.encode(pageData.toJson()));
  final bodyClasses = [
    if (type == PageType.standalone) 'page-standalone',
    if (requestContext.isExperimental) 'experimental',
  ];
  final userSession = userSessionData == null
      ? null
      : {
          'email': userSessionData.email,
          'image_url': userSessionData.imageUrl == null
              ? staticUrls.defaultProfilePng
              // Set image size to 30x30 pixels for faster loading, see:
              // https://developers.google.com/people/image-sizing
              : '${userSessionData.imageUrl}=s30',
        };
  final searchBannerHtml = _renderSearchBanner(
    type: type,
    platform: platform,
    sdk: sdk,
    publisherId: publisherId,
    searchQuery: searchQuery,
  );
  final values = {
    'is_experimental': requestContext.isExperimental,
    'is_logged_in': userSession != null,
    'dart_site_root': urls.dartSiteRoot,
    'oauth_client_id': activeConfiguration.pubSiteAudience,
    'user_session': userSession,
    'body_class': bodyClasses.join(' '),
    'no_index': noIndex,
    'favicon': faviconUrl ?? staticUrls.smallDartFavicon,
    'canonicalUrl': canonicalUrl,
    'pageDescription': pageDescription == null
        ? _defaultPageDescriptionEscaped
        : htmlEscape.convert(pageDescription),
    'title': htmlEscape.convert(title),
    'site_logo_url': staticUrls.pubDevLogo2xPng,
    // This is not escaped as it is already escaped by the caller.
    'content_html': contentHtml,
    'include_survey': includeSurvey,
    'include_highlight': type == PageType.package,
    'search_banner_html': searchBannerHtml,
    'schema_org_searchaction_json':
        isRoot ? encodeScriptSafeJson(_schemaOrgSearchAction) : null,
    'page_data_encoded': pageDataEncoded,
    'has_likes': requestContext.isExperimental,
    'my_liked_packages_url': urls.myLikedPackagesUrl(),
  };

  // TODO(zarah): update the 'layout' template to use urls from `shared/urls.dart`.
  return templateCache.renderTemplate('layout', values);
}

String _renderSearchBanner({
  @required PageType type,
  @required String platform,
  @required String sdk,
  @required String publisherId,
  @required SearchQuery searchQuery,
}) {
  final queryText = searchQuery?.query;
  final escapedSearchQuery =
      queryText == null ? null : htmlAttrEscape.convert(queryText);
  final platformDict = getPlatformDict(platform);
  String searchPlaceholder;
  if (publisherId != null) {
    searchPlaceholder = 'Search $publisherId packages';
  } else if (type == PageType.account) {
    searchPlaceholder = 'Search your packages';
  } else if (requestContext.isExperimental) {
    searchPlaceholder = getSdkDict(sdk).searchPackagesLabel;
  } else {
    searchPlaceholder = platformDict.searchPlatformPackagesLabel;
  }
  final searchFormUrl = searchQuery?.toSearchFormPath() ??
      SearchQuery.parse(platform: platform, publisherId: publisherId)
          .toSearchLink();
  final searchSort = searchQuery?.order == null
      ? null
      : serializeSearchOrder(searchQuery.order);
  String searchTabsHtml;
  if (type == PageType.landing) {
    searchTabsHtml =
        renderSearchTabs(platform: platform, sdk: sdk, isLanding: true);
  } else if (type == PageType.listing) {
    searchTabsHtml = renderSearchTabs(
        platform: platform, sdk: sdk, searchQuery: searchQuery);
  }
  String bannerClass;
  if (type == PageType.landing) {
    bannerClass = 'home-banner';
  } else if (type == PageType.listing) {
    bannerClass = 'medium-banner';
  } else {
    bannerClass = 'small-banner';
  }
  return templateCache.renderTemplate('shared/search_banner', {
    'banner_class': bannerClass,
    'show_details': type == PageType.listing,
    'show_landing': type == PageType.landing,
    'search_form_url': searchFormUrl,
    'search_query_placeholder': searchPlaceholder,
    'search_query_html': escapedSearchQuery,
    'search_sort_param': searchSort,
    'legacy_search_enabled': searchQuery?.includeLegacy ?? false,
    'search_tabs_html': searchTabsHtml,
    'landing_banner_image': _landingBannerImage(platform == 'flutter'),
    'landing_banner_alt':
        platform == 'flutter' ? 'Flutter packages' : 'Dart packages',
    'landing_blurb_html': platformDict.landingBlurb,
  });
}

String _landingBannerImage(bool isFlutter) {
  return isFlutter
      ? staticUrls.assets['img__flutter-packages-white_png']
      : staticUrls.assets['img__dart-packages-white_png'];
}

String renderSearchTabs({
  String platform,
  String sdk,
  SearchQuery searchQuery,
  bool isLanding = false,
}) {
  final String currentPlatform = platform ?? searchQuery?.platform;
  Map platformTabData(String tabText, String tabPlatform) {
    String url;
    if (searchQuery != null) {
      final newQuery =
          searchQuery.change(platform: tabPlatform == null ? '' : tabPlatform);
      url = newQuery.toSearchLink();
    } else {
      final List<String> pathParts = [''];
      if (tabPlatform != null) pathParts.add(tabPlatform);
      if (!isLanding) pathParts.add('packages');
      url = pathParts.join('/');
      if (url.isEmpty) {
        url = '/';
      }
    }
    return {
      'text': tabText,
      'href': htmlAttrEscape.convert(url),
      'active': tabPlatform == currentPlatform
    };
  }

  final currentSdk = sdk ?? searchQuery?.sdk ?? SdkTagValue.any;
  Map sdkTabData(String label, String tabSdk) {
    String url;
    if (searchQuery != null) {
      url = searchQuery.change(sdk: tabSdk).toSearchLink();
    } else {
      url = urls.searchUrl(sdk: tabSdk);
    }
    return {
      'text': label,
      'href': htmlAttrEscape.convert(url),
      'active': tabSdk == currentSdk,
    };
  }

  if (requestContext.isExperimental) {
    final values = {
      'tabs': [
        sdkTabData('Dart', SdkTagValue.dart),
        sdkTabData('Flutter', SdkTagValue.flutter),
        sdkTabData('Any', SdkTagValue.any),
      ],
    };
    return templateCache.renderTemplate('shared/search_tabs', values);
  } else {
    final values = {
      'tabs': [
        platformTabData('Flutter', KnownPlatforms.flutter),
        platformTabData('Web', KnownPlatforms.web),
        platformTabData('All', null),
      ],
    };
    return templateCache.renderTemplate('shared/search_tabs', values);
  }
}

final String _defaultPageDescriptionEscaped = htmlEscape.convert(
    'Pub is the package manager for the Dart programming language, containing reusable '
    'libraries & packages for Flutter, AngularDart, and general Dart programs.');

const _schemaOrgSearchAction = {
  '@context': 'http://schema.org',
  '@type': 'WebSite',
  'url': '${urls.siteRoot}/',
  'potentialAction': {
    '@type': 'SearchAction',
    'target': '${urls.siteRoot}/packages?q={search_term_string}',
    'query-input': 'required name=search_term_string',
  },
};
