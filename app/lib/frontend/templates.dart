// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library pub_dartlang_org.templates;

import 'dart:convert';

import 'package:pana/models.dart' show SuggestionLevel;

import '../scorecard/models.dart';
import '../shared/analyzer_client.dart';
import '../shared/email.dart' show EmailAddress;
import '../shared/markdown.dart';
import '../shared/platform.dart';
import '../shared/search_service.dart';
import '../shared/urls.dart' as urls;
import '../shared/utils.dart';

import 'color.dart';
import 'models.dart';
import 'static_files.dart';
import 'template_consts.dart';
import 'templates/_cache.dart';
import 'templates/_utils.dart';
import 'templates/layout.dart';
import 'templates/misc.dart';

/// [TemplateService] singleton instance.
/// TODO: remove after https://github.com/dart-lang/pub-dartlang-dart/issues/1907 gets fixed
final templateService = new TemplateService();

/// Used for rendering HTML pages for pub.dartlang.org.
class TemplateService {
  /// Renders the `views/pkg/versions/index` template.
  String renderPkgVersionsPage(String package, List<PackageVersion> versions,
      List<Uri> versionDownloadUrls) {
    assert(versions.length == versionDownloadUrls.length);

    final stableVersionRows = [];
    final devVersionRows = [];
    PackageVersion latestDevVersion;
    for (int i = 0; i < versions.length; i++) {
      final PackageVersion version = versions[i];
      final String url = versionDownloadUrls[i].toString();
      final rowHtml = _renderVersionTableRow(version, url);
      if (version.semanticVersion.isPreRelease) {
        latestDevVersion ??= version;
        devVersionRows.add(rowHtml);
      } else {
        stableVersionRows.add(rowHtml);
      }
    }

    final htmlBlocks = <String>[];
    if (stableVersionRows.isNotEmpty && devVersionRows.isNotEmpty) {
      htmlBlocks.add(
          '<p>The latest dev release was <a href="#dev">${latestDevVersion.version}</a> '
          'on ${latestDevVersion.shortCreated}.</p>');
    }
    if (stableVersionRows.isNotEmpty) {
      htmlBlocks.add(templateCache.renderTemplate('pkg/versions/index', {
        'id': 'stable',
        'kind': 'Stable',
        'package': {'name': package},
        'version_table_rows': stableVersionRows,
      }));
    }
    if (devVersionRows.isNotEmpty) {
      htmlBlocks.add(templateCache.renderTemplate('pkg/versions/index', {
        'id': 'dev',
        'kind': 'Dev',
        'package': {'name': package},
        'version_table_rows': devVersionRows,
      }));
    }
    return renderLayoutPage(PageType.package, htmlBlocks.join(),
        title: '$package package - All Versions',
        canonicalUrl: urls.pkgPageUrl(package, includeHost: true));
  }

  String _renderVersionTableRow(PackageVersion version, String downloadUrl) {
    final versionData = {
      'package': version.package,
      'version': version.version,
      'version_url': urls.pkgPageUrl(version.package, version: version.version),
      'short_created': version.shortCreated,
      'dartdocs_url':
          _attr(urls.pkgDocUrl(version.package, version: version.version)),
      'download_url': _attr(downloadUrl),
      'icons': staticUrls.versionsTableIcons,
    };
    return templateCache.renderTemplate(
        'pkg/versions/version_row', versionData);
  }

  String _renderAnalysisDepRow(PkgDependency pd) {
    return templateCache.renderTemplate('pkg/analysis_dep_row', {
      'is_hosted': pd.isHosted,
      'package': pd.package,
      'package_url': urls.pkgPageUrl(pd.package),
      'constraint': pd.constraint?.toString(),
      'resolved': pd.resolved?.toString(),
      'available': pd.available?.toString(),
    });
  }

  /// Renders the `views/pkg/analysis_tab.mustache` template.
  String renderAnalysisTab(String package, String sdkConstraint,
      ScoreCardData card, AnalysisView analysis) {
    if (card == null || analysis == null || !analysis.hasAnalysisData) {
      return null;
    }

    String statusText;
    switch (analysis.panaReportStatus) {
      case ReportStatus.aborted:
        statusText = 'aborted';
        break;
      case ReportStatus.failed:
        statusText = 'tool failures';
        break;
      case ReportStatus.success:
        statusText = 'completed';
        break;
      default:
        break;
    }

    List<Map> prepareDependencies(List<PkgDependency> list) {
      if (list == null || list.isEmpty) return const [];
      return list.map((pd) => {'row_html': _renderAnalysisDepRow(pd)}).toList();
    }

    final hasSdkConstraint = sdkConstraint != null && sdkConstraint.isNotEmpty;
    final directDeps = prepareDependencies(analysis.directDependencies);
    final transitiveDeps = prepareDependencies(analysis.transitiveDependencies);
    final devDeps = prepareDependencies(analysis.devDependencies);
    final hasDependency = hasSdkConstraint ||
        directDeps.isNotEmpty ||
        transitiveDeps.isNotEmpty ||
        devDeps.isNotEmpty;

    final Map<String, dynamic> data = {
      'package': package,
      'show_discontinued': card.isDiscontinued,
      'show_outdated': card.isObsolete,
      'show_legacy': card.isLegacy,
      'show_analysis': !card.isSkipped,
      'analysis_tab_url': urls.analysisTabUrl(package),
      'date_completed': analysis.timestamp == null
          ? null
          : shortDateFormat.format(analysis.timestamp),
      'analysis_status': statusText,
      'dart_sdk_version': analysis.dartSdkVersion,
      'pana_version': analysis.panaVersion,
      'flutter_version': analysis.flutterVersion,
      'platforms_html': analysis.platforms
              ?.map((p) => getPlatformDict(p, nullIfMissing: true)?.name ?? p)
              ?.join(', ') ??
          '<i>unsure</i>',
      'platforms_reason_html': markdownToHtml(analysis.platformsReason, null),
      'analysis_suggestions_html':
          _renderSuggestionBlockHtml('Analysis', analysis.panaSuggestions),
      'health_suggestions_html':
          _renderSuggestionBlockHtml('Health', analysis.healthSuggestions),
      'maintenance_suggestions_html': _renderSuggestionBlockHtml(
          'Maintenance', analysis.maintenanceSuggestions),
      'has_dependency': hasDependency,
      'dependencies': {
        'has_sdk': hasSdkConstraint,
        'sdk': sdkConstraint,
        'has_direct': hasSdkConstraint || directDeps.isNotEmpty,
        'direct': directDeps,
        'has_transitive': transitiveDeps.isNotEmpty,
        'transitive': transitiveDeps,
        'has_dev': devDeps.isNotEmpty,
        'dev': devDeps,
      },
      'score_bars': _renderScoreBars(card),
    };

    return templateCache.renderTemplate('pkg/analysis_tab', data);
  }

  String _renderSuggestionBlockHtml(
      String header, List<Suggestion> suggestions) {
    if (suggestions == null || suggestions.isEmpty) {
      return null;
    }

    final hasIssues = suggestions.any((s) => s.isError || s.isWarning);
    final label =
        hasIssues ? '$header issues and suggestions' : '$header suggestions';

    final mappedValues = suggestions.map((suggestion) {
      return {
        'icon_class': _suggestionIconClass(suggestion.level),
        'title_html':
            _renderSuggestionTitle(suggestion.title, suggestion.score),
        'description_html': markdownToHtml(suggestion.description, null),
        'suggestion_help_html': getSuggestionHelpMessage(suggestion.code),
      };
    }).toList();

    final data = <String, dynamic>{
      'label': label,
      'suggestions': mappedValues,
    };
    return templateCache.renderTemplate('pkg/analysis_suggestion_block', data);
  }

  Map<String, Object> _pkgShowPageValues(
      Package package,
      List<PackageVersion> versions,
      List<Uri> versionDownloadUrls,
      PackageVersion selectedVersion,
      PackageVersion latestStableVersion,
      PackageVersion latestDevVersion,
      int totalNumberOfVersions,
      ScoreCardData card,
      AnalysisView analysis,
      bool isFlutterPackage) {
    String readmeFilename;
    String renderedReadme;
    final homepageUrl = selectedVersion.homepage;
    if (selectedVersion.readme != null) {
      readmeFilename = selectedVersion.readme.filename;
      renderedReadme = renderFile(selectedVersion.readme, homepageUrl);
    }

    String changelogFilename;
    String renderedChangelog;
    if (selectedVersion.changelog != null) {
      changelogFilename = selectedVersion.changelog.filename;
      renderedChangelog = renderFile(selectedVersion.changelog, homepageUrl);
    }

    String exampleFilename;
    String renderedExample;
    if (selectedVersion.example != null) {
      exampleFilename = selectedVersion.example.filename;
      renderedExample = renderFile(selectedVersion.example, homepageUrl);
      if (renderedExample != null) {
        renderedExample = '<p style="font-family: monospace">'
            '<b>${htmlEscape.convert(exampleFilename)}</b>'
            '</p>\n'
            '$renderedExample';
      }
    }

    final versionTableRows = [];
    for (int i = 0; i < versions.length; i++) {
      final PackageVersion version = versions[i];
      final String url = versionDownloadUrls[i].toString();
      versionTableRows.add(_renderVersionTableRow(version, url));
    }

    final bool shouldShowDev =
        latestStableVersion.semanticVersion < latestDevVersion.semanticVersion;
    final bool shouldShow =
        selectedVersion != latestStableVersion || shouldShowDev;

    final List<Map<String, String>> tabs = <Map<String, String>>[];
    void addFileTab(String id, String title, String content) {
      if (content != null) {
        tabs.add({
          'id': id,
          'title': title,
          'content': content,
        });
      }
    }

    addFileTab('readme', readmeFilename, renderedReadme);
    addFileTab('changelog', changelogFilename, renderedChangelog);
    addFileTab('example', 'Example', renderedExample);
    if (tabs.isNotEmpty) {
      tabs.first['active'] = '-active';
    }
    final isAwaiting = card == null ||
        analysis == null ||
        (!card.isSkipped && !analysis.hasPanaSummary);
    String documentationUrl = selectedVersion.documentation;
    if (documentationUrl != null &&
        (documentationUrl.startsWith('https://www.dartdocs.org/') ||
            documentationUrl.startsWith('http://www.dartdocs.org/') ||
            documentationUrl.startsWith('https://pub.dartlang.org/') ||
            documentationUrl.startsWith('http://pub.dartlang.org/'))) {
      documentationUrl = null;
    }
    final dartdocsUrl = urls.pkgDocUrl(
      package.name,
      version: selectedVersion.version,
      isLatest: selectedVersion.version == package.latestVersion,
    );
    final packageLinks = selectedVersion.packageLinks;

    final links = <Map<String, dynamic>>[];
    void addLink(
      String href,
      String label, {
      bool detectServiceProvider = false,
    }) {
      if (href == null || href.isEmpty) {
        return;
      }
      if (detectServiceProvider) {
        final providerName = urls.inferServiceProviderName(href);
        if (providerName != null) {
          label += ' ($providerName)';
        }
      }
      links.add(<String, dynamic>{'href': href, 'label': label});
    }

    if (packageLinks.repositoryUrl != packageLinks.homepageUrl) {
      addLink(homepageUrl, 'Homepage');
    }
    addLink(packageLinks.repositoryUrl, 'Repository',
        detectServiceProvider: true);
    addLink(packageLinks.issueTrackerUrl, 'View/report issues');
    addLink(packageLinks.documentationUrl, 'Documentation');
    addLink(dartdocsUrl, 'API reference');

    final values = {
      'package': {
        'name': package.name,
        'selected_version': {
          'version': selectedVersion.id,
        },
        'latest': {
          'should_show': shouldShow,
          'should_show_dev': shouldShowDev,
          'stable_url': urls.pkgPageUrl(package.name),
          'stable_name': latestStableVersion.version,
          'dev_url':
              urls.pkgPageUrl(package.name, version: latestDevVersion.version),
          'dev_name': latestDevVersion.version,
        },
        'tags_html': renderTags(
          analysis?.platforms,
          isAwaiting: isAwaiting,
          isDiscontinued: card?.isDiscontinued ?? false,
          isLegacy: card?.isLegacy ?? false,
          isObsolete: card?.isObsolete ?? false,
        ),
        'description': selectedVersion.pubspec.description,
        // TODO: make this 'Authors' if PackageVersion.authors is a list?!
        'authors_title': 'Author',
        'authors_html': _getAuthorsHtml(selectedVersion.pubspec.authors),
        'links': links,
        // TODO: make this 'Uploaders' if Package.uploaders is > 1?!
        'uploaders_title': 'Uploader',
        'uploaders_html': _getAuthorsHtml(package.uploaderEmails),
        'short_created': selectedVersion.shortCreated,
        'license_html': _renderLicenses(homepageUrl, analysis?.licenses),
        'score_box_html': renderScoreBox(card?.overallScore,
            isSkipped: card?.isSkipped ?? false,
            isNewPackage: package.isNewPackage()),
        'dependencies_html': _renderDependencyList(analysis),
        'analysis_html': renderAnalysisTab(package.name,
            selectedVersion.pubspec.sdkConstraint, card, analysis),
        'schema_org_pkgmeta_json':
            json.encode(_schemaOrgPkgMeta(package, selectedVersion, analysis)),
      },
      'version_table_rows': versionTableRows,
      'show_versions_link': totalNumberOfVersions > versions.length,
      'versions_url': urls.pkgVersionsUrl(package.name),
      'tabs': tabs,
      'has_no_file_tab': tabs.isEmpty,
      'version_count': '$totalNumberOfVersions',
      'icons': staticUrls.versionsTableIcons,
    };
    return values;
  }

  Map<String, dynamic> _renderScoreBars(ScoreCardData card) {
    String renderScoreBar(double score, Brush brush) {
      return templateCache.renderTemplate('pkg/score_bar', {
        'percent': formatScore(score ?? 0.0),
        'score': formatScore(score),
        'background': brush.background.toString(),
        'color': brush.color.toString(),
        'shadow': brush.shadow.toString(),
      });
    }

    final isSkipped = card?.isSkipped ?? false;
    final healthScore = isSkipped ? null : card?.healthScore;
    final maintenanceScore = isSkipped ? null : card?.maintenanceScore;
    final popularityScore = card?.popularityScore;
    final overallScore = card?.overallScore ?? 0.0;
    return {
      'health_html':
          renderScoreBar(healthScore, genericScoreBrush(healthScore)),
      'maintenance_html':
          renderScoreBar(maintenanceScore, genericScoreBrush(maintenanceScore)),
      'popularity_html':
          renderScoreBar(popularityScore, genericScoreBrush(popularityScore)),
      'overall_html':
          renderScoreBar(overallScore, overallScoreBrush(overallScore)),
    };
  }

  String _renderLicenses(String baseUrl, List<LicenseFile> licenses) {
    if (licenses == null || licenses.isEmpty) return null;
    return licenses.map((license) {
      final String escapedName = htmlEscape.convert(license.shortFormatted);
      String html = escapedName;

      if (license.url != null && license.path != null) {
        final String escapedLink = htmlAttrEscape.convert(license.url);
        final String escapedPath = htmlEscape.convert(license.path);
        html += ' (<a href="$escapedLink">$escapedPath</a>)';
      } else if (license.path != null) {
        final String escapedPath = htmlEscape.convert(license.path);
        html += ' ($escapedPath)';
      }
      return html;
    }).join('<br/>');
  }

  String _renderDependencyList(AnalysisView analysis) {
    if (analysis == null ||
        !analysis.hasPanaSummary ||
        analysis.directDependencies == null) return null;
    final List<String> packages =
        analysis.directDependencies.map((pd) => pd.package).toList()..sort();
    if (packages.isEmpty) return null;
    return packages
        .map((p) => '<a href="${urls.pkgPageUrl(p)}">$p</a>')
        .join(', ');
  }

  String _renderInstallTab(Package package, PackageVersion selectedVersion,
      bool isFlutterPackage, List<String> platforms) {
    List importExamples;
    if (selectedVersion.libraries.contains('${package.id}.dart')) {
      importExamples = [
        {
          'package': package.id,
          'library': '${package.id}.dart',
        },
      ];
    } else {
      importExamples = selectedVersion.libraries.map((library) {
        return {
          'package': selectedVersion.packageKey.id,
          'library': library,
        };
      }).toList();
    }

    final executables = selectedVersion.pubspec.executables?.keys?.toList();
    executables?.sort();
    final hasExecutables = executables != null && executables.isNotEmpty;

    final exampleVersionConstraint = '^${selectedVersion.version}';

    final bool usePubGet = !isFlutterPackage ||
        platforms == null ||
        platforms.isEmpty ||
        platforms.length > 1 ||
        platforms.first != KnownPlatforms.flutter;

    final bool useFlutterPackagesGet = isFlutterPackage ||
        (platforms != null && platforms.contains(KnownPlatforms.flutter));

    String editorSupportedToolHtml;
    if (usePubGet && useFlutterPackagesGet) {
      editorSupportedToolHtml =
          '<code>pub get</code> or <code>flutter packages get</code>';
    } else if (useFlutterPackagesGet) {
      editorSupportedToolHtml = '<code>flutter packages get</code>';
    } else {
      editorSupportedToolHtml = '<code>pub get</code>';
    }

    return templateCache.renderTemplate('pkg/install_tab', {
      'use_as_an_executable': hasExecutables,
      'use_as_a_library': !hasExecutables || importExamples.isNotEmpty,
      'package': package.name,
      'example_version_constraint': exampleVersionConstraint,
      'has_libraries': importExamples.isNotEmpty,
      'import_examples': importExamples,
      'use_pub_get': usePubGet,
      'use_flutter_packages_get': useFlutterPackagesGet,
      'show_editor_support': usePubGet || useFlutterPackagesGet,
      'editor_supported_tool_html': editorSupportedToolHtml,
      'executables': executables,
    });
  }

  /// Renders the `views/pkg/show.mustache` template.
  String renderPkgShowPage(
      Package package,
      bool isVersionPage,
      List<PackageVersion> versions,
      List<Uri> versionDownloadUrls,
      PackageVersion selectedVersion,
      PackageVersion latestStableVersion,
      PackageVersion latestDevVersion,
      int totalNumberOfVersions,
      ScoreCardData card,
      AnalysisView analysis) {
    assert(versions.length == versionDownloadUrls.length);
    final int platformCount = card?.platformTags?.length ?? 0;
    final String singlePlatform =
        platformCount == 1 ? card.platformTags.single : null;
    final bool hasPlatformSearch =
        singlePlatform != null && singlePlatform != KnownPlatforms.other;
    final bool hasOnlyFlutterPlatform =
        singlePlatform == KnownPlatforms.flutter;
    final bool isFlutterPackage = hasOnlyFlutterPlatform ||
        latestStableVersion.pubspec.dependsOnFlutterSdk ||
        latestStableVersion.pubspec.hasFlutterPlugin;

    final Map<String, Object> values = _pkgShowPageValues(
      package,
      versions,
      versionDownloadUrls,
      selectedVersion,
      latestStableVersion,
      latestDevVersion,
      totalNumberOfVersions,
      card,
      analysis,
      isFlutterPackage,
    );
    values['search_deps_link'] =
        urls.searchUrl(q: 'dependency:${package.name}');
    values['install_tab_html'] = _renderInstallTab(
        package, selectedVersion, isFlutterPackage, analysis?.platforms);
    final content = templateCache.renderTemplate('pkg/show', values);
    final packageAndVersion = isVersionPage
        ? '${selectedVersion.package} ${selectedVersion.version}'
        : selectedVersion.package;
    var pageDescription = packageAndVersion;
    if (isFlutterPackage) {
      pageDescription += ' Flutter and Dart package';
    } else {
      pageDescription += ' Dart package';
    }
    final pageTitle =
        '$packageAndVersion | ${isFlutterPackage ? 'Flutter' : 'Dart'} Package';
    pageDescription += ' - ${selectedVersion.ellipsizedDescription}';
    final canonicalUrl =
        isVersionPage ? urls.pkgPageUrl(package.name, includeHost: true) : null;
    return renderLayoutPage(
      PageType.package,
      content,
      title: pageTitle,
      pageDescription: pageDescription,
      faviconUrl: isFlutterPackage ? staticUrls.flutterLogo32x32 : null,
      canonicalUrl: canonicalUrl,
      platform: hasPlatformSearch ? singlePlatform : null,
      noIndex: package.isDiscontinued == true, // isDiscontinued may be null
    );
  }
}

String _getAuthorsHtml(List<String> authors) {
  return (authors ?? const []).map((String value) {
    final EmailAddress author = new EmailAddress.parse(value);
    final escapedName = htmlEscape.convert(author.name ?? author.email);
    if (author.email != null) {
      final escapedEmail = htmlAttrEscape.convert(author.email);
      final emailSearchUrl = htmlAttrEscape.convert(
          new SearchQuery.parse(query: 'email:${author.email}').toSearchLink());
      return '<span class="author">'
          '<a href="mailto:$escapedEmail" title="Email $escapedEmail">'
          '<i class="email-icon"></i></a> '
          '<a href="$emailSearchUrl" title="Search packages with $escapedEmail" rel="nofollow">'
          '<i class="search-icon"></i></a> '
          '$escapedName'
          '</span>';
    } else {
      return '<span class="author">$escapedName</span>';
    }
  }).join('<br/>');
}

Map _schemaOrgPkgMeta(Package p, PackageVersion pv, AnalysisView analysis) {
  final Map map = {
    '@context': 'http://schema.org',
    '@type': 'SoftwareSourceCode',
    'name': pv.package,
    'version': pv.version,
    'description': '${pv.package} - ${pv.pubspec.description}',
    'url': urls.pkgPageUrl(pv.package, includeHost: true),
    'dateCreated': p.created.toIso8601String(),
    'dateModified': pv.created.toIso8601String(),
    'programmingLanguage': 'Dart',
    'image':
        '${urls.siteRoot}${staticUrls.staticPath}/img/dart-logo-400x400.png'
  };
  final licenses = analysis?.licenses;
  final firstUrl =
      licenses?.firstWhere((lf) => lf.url != null, orElse: () => null)?.url;
  if (firstUrl != null) {
    map['license'] = firstUrl;
  }
  // TODO: add http://schema.org/codeRepository for github and gitlab links
  return map;
}

String _attr(String value) {
  if (value == null) return null;
  return htmlAttrEscape.convert(value);
}

String _suggestionIconClass(String level) {
  if (level == null) return 'suggestion-icon-info';
  switch (level) {
    case SuggestionLevel.error:
      return 'suggestion-icon-danger';
    case SuggestionLevel.warning:
      return 'suggestion-icon-warning';
    default:
      return 'suggestion-icon-info';
  }
}

String _renderSuggestionTitle(String title, double score) {
  final formattedScore = _formatSuggestionScore(score);
  if (formattedScore != null) {
    title = '$title ($formattedScore)';
  }
  return markdownToHtml(title, null);
}

String _formatSuggestionScore(double score) {
  if (score == null || score == 0.0) {
    return null;
  }
  final intValue = score.round();
  final isInt = intValue.toDouble() == score;
  final formatted = isInt ? intValue.toString() : score.toStringAsFixed(2);
  return '-$formatted points';
}
