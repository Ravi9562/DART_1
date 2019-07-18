// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../shared/handlers.dart';

import 'account.dart';
import 'admin.dart';
import 'atom_feed.dart';
import 'custom_api.dart';
import 'documentation.dart';
import 'landing.dart';
import 'listing.dart';
import 'misc.dart';
import 'package.dart';
import 'publisher.dart';

part 'routes.g.dart';

/// The main routes that are processed by the pub site's frontend.
class PubSiteService {
  final Handler _pubServerHandler;
  PubSiteService(this._pubServerHandler);

  Router get router => _$PubSiteServiceRouter(this);

  // ****
  // **** AppEngine health checks
  // ****

  @Route.get('/liveness_check')
  Future<Response> livenessCheck(Request request) async => htmlResponse('OK');

  @Route.get('/readiness_check')
  Future<Response> readinessCheck(Request request) async =>
      readinessCheckHandler(request);

  // ****
  // **** pub client APIs
  // ****

  /// Getting information about all versions of a package.
  ///
  /// GET /api/packages/<package-name>
  /// https://github.com/dart-lang/pub_server/blob/master/lib/shelf_pubserver.dart#L28-L49
  @Route.get('/api/packages/<package>')
  Future<Response> listVersions(Request request, String package) async =>
      _pubServerHandler(request);

  /// Getting information about a specific (package, version) pair.
  ///
  /// GET /api/packages/<package-name>/versions/<version-name>
  ///
  /// https://github.com/dart-lang/pub_server/blob/master/lib/shelf_pubserver.dart#L51-L65
  @Route.get('/api/packages/<package>/versions/<version>')
  Future<Response> versionInfo(
          Request request, String package, String version) async =>
      _pubServerHandler(request);

  /// Downloading package.
  ///
  /// GET /api/packages/<package-name>/versions/<version-name>.tar.gz
  /// https://github.com/dart-lang/pub_server/blob/master/lib/shelf_pubserver.dart#L67-L75
  @Route.get('/api/packages/<package>/versions/<version>.tar.gz')
  @Route.get('/packages/<package>/versions/<version>.tar.gz')
  Future<Response> versionArchive(
          Request request, String package, String version) async =>
      _pubServerHandler(request);

  /// Start async upload.
  ///
  /// GET /api/packages/versions/new
  /// https://github.com/dart-lang/pub_server/blob/master/lib/shelf_pubserver.dart#L77-L107
  @Route.get('/api/packages/versions/new')
  Future<Response> startUpload(Request request) async =>
      _pubServerHandler(request);

  /// Finish async upload.
  ///
  /// GET /api/packages/versions/newUploadFinish
  /// https://github.com/dart-lang/pub_server/blob/master/lib/shelf_pubserver.dart#L77-L107
  @Route.get('/api/packages/versions/newUploadFinish')
  Future<Response> finishUpload(Request request) async =>
      _pubServerHandler(request);

  /// Adding a new uploader
  ///
  /// POST /api/packages/<package-name>/uploaders
  /// https://github.com/dart-lang/pub_server/blob/master/lib/shelf_pubserver.dart#L109-L116
  @Route.post('/api/packages/<package>/uploaders')
  Future<Response> addUploader(Request request, String package) async =>
      _pubServerHandler(request);

  /// Removing an existing uploader.
  ///
  /// DELETE /api/packages/<package-name>/uploaders/<uploader-email>
  /// https://github.com/dart-lang/pub_server/blob/master/lib/shelf_pubserver.dart#L118-L123
  @Route.delete('/api/packages/<package>/uploaders/<email>')
  Future<Response> removeUploader(
          Request request, String package, String email) async =>
      _pubServerHandler(request);

  // ****
  // **** Landing pages
  // ****

  /// Site index
  @Route.get('/')
  Future<Response> index(Request request) => indexLandingHandler(request);

  /// Flutter index
  @Route.get('/flutter')
  Future<Response> flutter(Request request) => flutterLandingHandler(request);

  /// Web index
  @Route.get('/web')
  Future<Response> web(Request request) => webLandingHandler(request);

  // ****
  // **** Listing pages
  // ****

  /// Default package listing page
  @Route.get('/packages')
  Future<Response> packages(Request request) => packagesHandlerHtml(request);

  @Route.get('/flutter/packages')
  Future<Response> flutterPackages(Request request) =>
      flutterPackagesHandlerHtml(request);

  @Route.get('/web/packages')
  Future<Response> webPackages(Request request) =>
      webPackagesHandlerHtml(request);

  // ****
  // **** Packages
  // ****

  @Route.get('/packages/<package>/versions/<version>')
  Future<Response> packageVersion(
          Request request, String package, String version) =>
      packageVersionHandlerHtml(request, package, versionName: version);

  @Route.get('/packages/<package>/admin')
  Future<Response> packageAdmin(Request request, String package) =>
      packageAdminHandler(request, package);

  @Route.get('/packages/<package>/versions')
  Future<Response> packageVersionsJson(Request request, String package) =>
      packageVersionsListHandler(request, package);

  @Route.get('/packages/<package>.json')
  Future<Response> packageJson(Request request, String package) =>
      packageShowHandlerJson(request, package);

  @Route.get('/packages/<package>')
  Future<Response> package(Request request, String package) =>
      packageVersionHandlerHtml(request, package);

  // ****
  // **** Documentation
  // ****

  @Route.get('/documentation/<package>/<version>/<path|[^]*>')
  Future<Response> documentation(
          Request request, String package, String version, String path) =>
      // TODO: pass in the [package] and [version] parameters, and maybe also the rest of the path.
      // TODO: investigate if _originalRequest is still needed
      documentationHandler(
          request.context['_originalRequest'] as Request ?? request);

  @Route.get('/documentation/<package>/<version>')
  @Route.get('/documentation/<package>/<version>/')
  Future<Response> documentationVersion(
          Request request, String package, String version) =>
      // TODO: pass in the [package] and [version] parameters, and maybe also the rest of the path.
      // TODO: investigate if _originalRequest is still needed
      documentationHandler(
          request.context['_originalRequest'] as Request ?? request);

  @Route.get('/documentation/<package>')
  @Route.get('/documentation/<package>/')
  Future<Response> documentationLatest(Request request, String package) =>
      // TODO: pass in the [package] parameter, or do redirect to /latest/ here
      // TODO: investigate if _originalRequest is still needed
      documentationHandler(
          request.context['_originalRequest'] as Request ?? request);

  // ****
  // **** Publishers
  // ****

  /// Renders the page where users can start creating a publisher.
  @Route.get('/create-publisher')
  Future<Response> createPublisherPage(Request request) =>
      createPublisherPageHandler(request);

  /// Starts publisher creation flow.
  @Route.post('/api/publisher/<publisherId>')
  Future<Response> createPublisherApi(Request request, String publisherId) =>
      createPublisherApiHandler(request, publisherId);

  /// Returns publisher data in a JSON form.
  @Route.get('/api/publisher/<publisherId>')
  Future<Response> getPublisherApi(Request request, String publisherId) =>
      getPublisherApiHandler(request, publisherId);

  /// Updates publisher data.
  @Route.put('/api/publisher/<publisherId>')
  Future<Response> putPublisherApi(Request request, String publisherId) =>
      putPublisherApiHandler(request, publisherId);

  /// Returns a publisher's member data and role in a JSON form.
  @Route.post('/api/publisher/<publisherId>/invite-member')
  Future<Response> invitePublisherMember(Request request, String publisherId) =>
      invitePublisherMemberHandler(request, publisherId);

  /// Returns publisher members data in a JSON form.
  @Route.get('/api/publisher/<publisherId>/members')
  Future<Response> getPublisherMembersApi(
          Request request, String publisherId) =>
      getPublisherMembersApiHandler(request, publisherId);

  /// Returns a publisher's member data and role in a JSON form.
  @Route.get('/api/publisher/<publisherId>/members/<userId>')
  Future<Response> getPublisherMemberDataApi(
          Request request, String publisherId, String userId) =>
      getPublisherMemberDataApiHandler(request, publisherId, userId);

  /// Updates a publisher's member data and role.
  @Route.put('/api/publisher/<publisherId>/members/<userId>')
  Future<Response> putPublisherMemberDataApi(
          Request request, String publisherId, String userId) =>
      putPublisherMemberDataApiHandler(request, publisherId, userId);

  /// Deletes a publisher's member.
  @Route.delete('/api/publisher/<publisherId>/members/<userId>')
  Future<Response> deletePublisherMemberDataApi(
          Request request, String publisherId, String userId) =>
      deletePublisherMemberDataApiHandler(request, publisherId, userId);

  // ****
  // **** Site content and metadata
  // ****

  /// Renders the Atom XML feed
  @Route.get('/feed.atom')
  Future<Response> atomFeed(Request request) => atomFeedHandler(request);

  /// Renders the help page
  @Route.get('/help')
  Future<Response> helpPage(Request request) => helpPageHandler(request);

  /// Renders the /robots.txt page
  @Route.get('/robots.txt')
  Future<Response> robotsTxt(Request request) => robotsTxtHandler(request);

  /// Renders the /sitemap.txt page
  @Route.get('/sitemap.txt')
  Future<Response> sitemapTxt(Request request) => siteMapTxtHandler(request);

  /// Renders static assets
  @Route.get('/favicon.ico')
  @Route.get('/static/<path|[^]*>')
  Future<Response> staticAsset(Request request) => staticsHandler(request);

  /// Controls the experimental cookie.
  @Route.get('/experimental')
  Future<Response> experimental(Request request) =>
      experimentalHandler(request);

  // ****
  // **** Account, authentication and user administration
  // ****

  /// Process oauth callbacks.
  @Route.get('/oauth/callback')
  Future<Response> oauthCallback(Request request) async =>
      oauthCallbackHandler(request);

  /// Renders the authorization confirmed page.
  @Route.get('/authorized')
  Future<Response> authorizationConfirmed(Request request) async =>
      authorizedHandler(request);

  /// Renders the page that initiates the confirmation and then finalizes the uploader.
  @Route.get('/admin/confirm/new-uploader/<package>/<email>/<nonce>')
  Future<Response> confirmUploader(
          Request request, String package, String email, String nonce) =>
      confirmNewUploaderHandler(request, package, email, nonce);

  /// Renders the page where an user can accept their invites/consents.
  @Route.get('/consent')
  Future<Response> consentPage(Request request) => consentPageHandler(request);

  /// Returns the consent request details.
  @Route.get('/api/account/consent/<consentId>')
  Future<Response> getAccountConsent(Request request, String consentId) =>
      getAccountConsentHandler(request, consentId);

  /// Accepts or declines the consent.
  @Route.put('/api/account/consent/<consentId>')
  Future<Response> putAccountConsent(Request request, String consentId) =>
      putAccountConsentHandler(request, consentId);

  // ****
  // **** Custom API
  // ****

  @Route.get('/api/account/options/packages/<package>')
  Future<Response> accountPkgOptions(Request request, String package) =>
      accountPkgOptionsHandler(request, package);

  @Route.get('/api/documentation/<package>')
  Future<Response> apiDocumentation(Request request, String package) =>
      apiDocumentationHandler(request, package);

  /// Exposes History entities.
  ///
  /// NOTE: experimental, do not rely on it
  @Route.get('/api/history')
  Future<Response> apiHistory(Request request) => apiHistoryHandler(request);

  @Route.get('/api/packages')
  Future<Response> apiPackages(Request request) async {
    if (request.requestedUri.queryParameters['compact'] == '1') {
      return apiPackagesCompactListHandler(request);
    } else {
      // /api/packages?page=<num>
      return apiPackagesHandler(request);
    }
  }

  @Route.get('/api/packages/<package>/metrics')
  Future<Response> apiPackageMetrics(Request request, String package) =>
      apiPackageMetricsHandler(request, package);

  @Route.get('/api/packages/<package>/options')
  Future<Response> getPackageOptions(Request request, String package) =>
      getPackageOptionsHandler(request, package);

  @Route.put('/api/packages/<package>/options')
  Future<Response> putPackageOptions(Request request, String package) =>
      putPackageOptionsHandler(request, package);

  @Route.get('/api/search')
  Future<Response> apiSearch(Request request) => apiSearchHandler(request);

  @Route.get('/debug')
  Future<Response> debug(Request request) async => debugResponse({
        'package': packageDebugStats(),
        'search': searchDebugStats(),
      });

  @Route.get('/packages.json')
  Future<Response> packagesJson(Request request) => packagesHandler(request);
}
