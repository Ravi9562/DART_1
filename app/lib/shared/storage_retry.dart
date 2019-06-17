import 'dart:io' show Platform;
import 'package:http_retry/http_retry.dart' show RetryClient;
import 'package:gcloud/storage.dart'
    show registerStorageService, Storage, storageService;
import 'package:gcloud/http.dart' show authClientService;

final _transientStatusCodes = {
  // See: https://cloud.google.com/storage/docs/xml-api/reference-status
  429,
  500,
  503,
};

/// Wrap the [storageService] exposed from `package:gcloud` and
/// `package:appengine` with [RetryClient]. And retry 500, 503, and 429 errors.
///
/// Note. this should not be used if uploading files that won't easily fit in
/// memory! As [RetryClient] will cache the entire request body in memory
/// in-order to do retries.
void registerStorageWithRetry() {
  // Ensure we're we have a client...
  if (authClientService != null) {
    throw StateError('gcloud/appengine must be setup');
  }
  // Find the projectId.
  final projectId = Platform.environment['GCLOUD_PROJECT'];
  if (projectId == null || projectId.isEmpty) {
    throw StateError('GCLOUD_PROJECT env var must be set');
  }

  // Create a that retries on transient errors
  final client = RetryClient(
    authClientService,
    when: (r) => _transientStatusCodes.contains(r.statusCode),
    // TOOD: Consider implementing whenError and handle DNS + handshake errors.
    //       These are safe, retrying after partially sending data is more
    //       sketchy, but probably safe in our application.
    retries: 5,
  );

  // Register a new storage service.
  registerStorageService(Storage(
    client,
    projectId,
  ));
}
