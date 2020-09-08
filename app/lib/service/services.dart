import 'dart:async' show FutureOr;

import 'package:appengine/appengine.dart';
import 'package:gcloud/db.dart';
import 'package:gcloud/service_scope.dart';
import 'package:gcloud/storage.dart';

import '../account/backend.dart';
import '../account/consent_backend.dart';
import '../account/google_oauth2.dart';
import '../admin/backend.dart';
import '../analyzer/analyzer_client.dart';
import '../dartdoc/backend.dart';
import '../dartdoc/dartdoc_client.dart';
import '../frontend/email_sender.dart';
import '../history/backend.dart';
import '../job/backend.dart';
import '../package/backend.dart';
import '../package/name_tracker.dart';
import '../package/search_adapter.dart';
import '../publisher/backend.dart';
import '../publisher/domain_verifier.dart';
import '../scorecard/backend.dart';
import '../search/backend.dart';
import '../search/mem_index.dart';
import '../search/search_client.dart';
import '../search/updater.dart';
import '../shared/configuration.dart';
import '../shared/popularity_storage.dart';
import '../shared/redis_cache.dart' show withCache;
import '../shared/storage.dart';
import '../shared/storage_retry.dart' show withStorageRetry;
import '../shared/urls.dart';
import '../shared/versions.dart';

import 'announcement/backend.dart';
import 'secret/backend.dart';
import 'spam/backend.dart';

/// Run [fn] with services;
///
///  * AppEngine: storage and datastore,
///  * Redis cache, and,
///  * storage wrapped with retry.
Future<void> withServices(FutureOr<void> Function() fn) async {
  return withAppEngineServices(() async {
    return await withStorageRetry(() async {
      return await withPubServices(fn);
    });
  });
}

/// Run [fn] with pub services that are shared between server instances, CLI
/// tools and integration tests.
Future<void> withPubServices(FutureOr<void> Function() fn) async {
  return fork(() async {
    registerAccountBackend(AccountBackend(dbService));
    registerAdminBackend(AdminBackend(dbService));
    registerAnalyzerClient(AnalyzerClient());
    registerAnnouncementBackend(AnnouncementBackend());
    registerAuthProvider(GoogleOauth2AuthProvider(
      <String>[
        activeConfiguration.pubClientAudience,
        activeConfiguration.pubSiteAudience,
        activeConfiguration.adminAudience,
      ],
    ));
    registerConsentBackend(ConsentBackend(dbService));
    registerDartdocBackend(
      DartdocBackend(
        dbService,
        await getOrCreateBucket(
            storageService, activeConfiguration.dartdocStorageBucketName),
      ),
    );
    registerDartdocClient(DartdocClient());
    registerDartSdkIndex(
        InMemoryPackageIndex.sdk(urlPrefix: dartSdkMainUrl(toolEnvSdkVersion)));
    registerEmailSender(
      activeConfiguration.gmailRelayServiceAccount != null &&
              activeConfiguration.gmailRelayImpersonatedGSuiteUser != null
          ? createGmailRelaySender(
              activeConfiguration.gmailRelayServiceAccount,
              activeConfiguration.gmailRelayImpersonatedGSuiteUser,
            )
          : loggingEmailSender,
    );
    registerHistoryBackend(HistoryBackend(dbService));
    registerJobBackend(JobBackend(dbService));
    registerNameTracker(NameTracker(dbService));
    registerPackageIndex(InMemoryPackageIndex());
    registerIndexUpdater(IndexUpdater(dbService, packageIndex));
    registerPopularityStorage(
      PopularityStorage(await getOrCreateBucket(
          storageService, activeConfiguration.popularityDumpBucketName)),
    );
    registerDomainVerifier(DomainVerifier());
    registerPublisherBackend(PublisherBackend(dbService));
    registerScoreCardBackend(ScoreCardBackend(dbService));
    registerSearchBackend(SearchBackend(dbService));
    registerSearchClient(SearchClient());
    registerSearchAdapter(SearchAdapter());
    registerSecretBackend(SecretBackend(dbService));
    registerSnapshotStorage(SnapshotStorage(await getOrCreateBucket(
        storageService, activeConfiguration.searchSnapshotBucketName)));
    registerSpamBackend(SpamBackend());
    registerTarballStorage(
      TarballStorage(
          storageService,
          await getOrCreateBucket(
              storageService, activeConfiguration.packageBucketName),
          null),
    );

    // depends on previously registered services
    registerPackageBackend(PackageBackend(dbService, tarballStorage));

    registerScopeExitCallback(announcementBackend.close);
    registerScopeExitCallback(() async => nameTracker.stopTracking());
    registerScopeExitCallback(snapshotStorage.close);
    registerScopeExitCallback(indexUpdater.close);
    registerScopeExitCallback(authProvider.close);
    registerScopeExitCallback(dartdocClient.close);
    registerScopeExitCallback(searchClient.close);
    registerScopeExitCallback(searchAdapter.close);
    registerScopeExitCallback(spamBackend.close);

    return await withCache(fn);
  });
}
