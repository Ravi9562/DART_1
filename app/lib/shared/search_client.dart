// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:gcloud/service_scope.dart' as ss;
import 'package:http/http.dart' as http;

import 'configuration.dart';
import 'search_service.dart';

/// Sets the search client.
void registerSearchClient(SearchClient client) =>
    ss.register(#_searchClient, client);

/// The active search client.
SearchClient get searchClient => ss.lookup(#_searchClient);

/// Client methods that access the search service and the internals of the
/// indexed data.
class SearchClient {
  /// The HTTP client used for making calls to our search service.
  final http.Client _httpClient = new http.Client();

  Future<PackageSearchResult> search(SearchQuery query) async {
    final httpHostPort = activeConfiguration.searchServicePrefix;
    final serviceUrlParams =
        new Uri(queryParameters: query.toServiceQueryParameters()).toString();
    final serviceUrl = '$httpHostPort/search$serviceUrlParams';
    final response = await _httpClient.get(serviceUrl);
    if (response.statusCode == searchIndexNotReadyCode) {
      // Search request before the service initialization completed.
      return null;
    }
    if (response.statusCode != 200) {
      // There has been an issue with the service
      throw new Exception(
          'Service returned status code ${response.statusCode}');
    }
    final result = new PackageSearchResult.fromJson(JSON.decode(response.body));
    if (!result.isLegit) {
      // Search request before the service initialization completed.
      return null;
    }
    return result;
  }

  Future close() async {
    _httpClient.close();
  }
}
