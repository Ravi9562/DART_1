// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:fake_gcloud/mem_datastore.dart';
import 'package:fake_gcloud/mem_storage.dart';
import 'package:gcloud/db.dart';
import 'package:gcloud/storage.dart';
import 'package:gcloud/service_scope.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:pub_dartlang_org/account/backend.dart';
import 'package:pub_dartlang_org/account/testing/fake_auth_provider.dart';
import 'package:pub_dartlang_org/frontend/handlers.dart';
import 'package:pub_dartlang_org/scorecard/backend.dart';
import 'package:pub_dartlang_org/search/backend.dart';
import 'package:pub_dartlang_org/search/handlers.dart';
import 'package:pub_dartlang_org/search/index_simple.dart';
import 'package:pub_dartlang_org/shared/configuration.dart';
import 'package:pub_dartlang_org/shared/handler_helpers.dart';
import 'package:pub_dartlang_org/shared/popularity_storage.dart';
import 'package:pub_dartlang_org/shared/redis_cache.dart';
import 'package:pub_dartlang_org/shared/search_client.dart';
import 'package:pub_dartlang_org/shared/services.dart';

import '../shared/utils.dart';
import 'test_models.dart';

/// Setup scoped services (including fake datastore with pre-populated base data
/// and fake storage) for tests.
void testWithServices(String name, Future fn()) {
  scopedTest(name, () async {
    // registering config with bad ports, as we won't access them via network
    registerActiveConfiguration(Configuration.fakePubServer(
      port: 0,
      storageBaseUrl: 'http://localhost:0',
    ));

    await withCache(() async {
      final db = DatastoreDB(MemDatastore());
      await db.commit(inserts: [
        foobarPackage,
        foobarStablePV,
        foobarDevPV,
        testUserA,
        hansUser,
        hydrogen.package,
        ...hydrogen.versions,
        helium.package,
        ...helium.versions,
        lithium.package,
        ...lithium.versions,
      ]);
      registerDbService(db);
      registerStorageService(MemStorage());

      await withPubServices(() async {
        popularityStorage.updateValues({
          hydrogen.package.name: 0.8,
          helium.package.name: 1.0,
          lithium.package.name: 0.7,
        });

        await scoreCardBackend.updateReport(
            helium.package.name,
            helium.package.latestVersion,
            generatePanaReport(platformTags: ['flutter']));
        await scoreCardBackend.updateScoreCard(
            helium.package.name, helium.package.latestVersion);

        await fork(() async {
          registerAccountBackend(
              AccountBackend(db, authProvider: FakeAuthProvider()));

          registerPackageIndex(SimplePackageIndex());
          packageIndex.addPackage(
              await searchBackend.loadDocument(hydrogen.package.name));
          packageIndex.addPackage(
              await searchBackend.loadDocument(helium.package.name));
          packageIndex.addPackage(
              await searchBackend.loadDocument(lithium.package.name));
          await packageIndex.merge();

          registerSearchClient(
              SearchClient(httpClient(handler: searchServiceHandler)));

          registerScopeExitCallback(searchClient.close);

          await fork(() async {
            await fn();
          });
        });
      });
    });
  });
}

/// Returns a HTTP client that bridges HTTP requests and shelf handlers without
/// the actual HTTP transport layer.
///
/// If [handler] is not specified, it will use the default frontend handler.
http_testing.MockClient httpClient({
  shelf.Handler handler,
  String authToken,
}) {
  handler ??= createAppHandler(null);
  handler = wrapHandler(
    Logger.detached('test'),
    handler,
    sanitize: true,
  );
  return http_testing.MockClient(
      _wrapShelfHandler(handler, authToken: authToken));
}

http_testing.MockClientHandler _wrapShelfHandler(
  shelf.Handler handler, {
  String authToken,
}) {
  return (rq) async {
    final shelfRq = shelf.Request(
      rq.method,
      rq.url,
      body: rq.body,
      headers: <String, String>{
        if (authToken != null) 'authorization': 'bearer $authToken',
        ...rq.headers,
      },
    );
    final rs = await handler(shelfRq);
    return http.Response(
      await rs.readAsString(),
      rs.statusCode,
      headers: rs.headers,
    );
  };
}
