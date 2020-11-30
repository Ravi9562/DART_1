// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

/// Validates the HTML content and throws ArgumentError if any of the
/// following issues are present:
/// - Canonical URL has invalid format or value.
/// - Inline JavaScript actions are present (e.g. `onclick`).
/// - Links with `<a target="_blank">` do not have `rel="noopener"`.
/// - `<script> tags have no `src` attribute or have content (except `ld+json`
///   meta content).
void parseAndValidateHtml(String html) {
  if (html.startsWith('<html>')) {
    html = '<!DOCTYPE html>\n$html';
  }
  validateHtml(parser.HtmlParser(html, strict: true).parse());
}

/// Validates the parsed HTML content and throws ArgumentError if any of the
/// following issues are present:
/// - Inline JavaScript actions are present (e.g. `onclick`).
/// - Links with `<a target="_blank">` do not have `rel="repooner"`.
/// - `<script> tags have no `src` attribute or have content (except `ld+json`
///   meta content).
void validateHtml(Node root) {
  List<Element> elements;
  List<Element> links;
  List<Element> scripts;

  if (root is DocumentFragment) {
    elements = root.querySelectorAll('*');
    links = root.querySelectorAll('a');
    scripts = root.querySelectorAll('script');
  } else if (root is Document) {
    _validateCanonicalLink(root.querySelector('head'));
    elements = root.querySelectorAll('*');
    links = root.querySelectorAll('a');
    scripts = root.querySelectorAll('script');
  } else {
    throw ArgumentError('Unknown html element type: $root');
  }

  // No inline JS attribute
  for (Element elem in elements) {
    for (final attr in elem.attributes.keys) {
      final name = attr.toString();
      if (name.toLowerCase().startsWith('on')) {
        throw ArgumentError(
            'No inline JS attribute is allowed, found: ${elem.outerHtml}.');
      }
    }
  }

  // All <a target="_blank"> links must have rel="noopener"
  for (Element elem in links) {
    if (elem.attributes['target'] == '_blank') {
      final rel = elem.attributes['rel'];
      if (!rel.split(' ').contains('noopener')) {
        throw ArgumentError(
            '_blank links must have rel=noopener, found: ${elem.outerHtml}.');
      }
    }
  }

  // No inline script tag.
  for (Element elem in scripts) {
    if (elem.attributes['type'] == 'application/ld+json') {
      if (elem.attributes.length != 1) {
        throw ArgumentError(
            'Only a single attribute is allowed on ld+json, found: ${elem.outerHtml}');
      }
      if (elem.text.trim().isEmpty) {
        throw ArgumentError('ld+json element must not be empty.');
      }
      // trigger parsing of the content
      json.decode(elem.text);
    } else {
      final src = elem.attributes['src'];
      if (src == null || src.isEmpty) {
        throw ArgumentError(
            'script tag must have src attribute, found: ${elem.parent?.outerHtml}');
      }
      if (elem.text.trim().isNotEmpty) {
        throw ArgumentError(
            'script tag must text content must be empty, found: ${elem.outerHtml}');
      }
    }
  }
}

/// "Google Search result usually points to the canonical page, unless one of
/// the duplicates is explicitly better suited for a user."
/// https://developers.google.com/search/docs/advanced/crawling/consolidate-duplicate-urls
///
/// To make sure we optimize our ranking, we should have a canonical URL for
/// every content we serve. This helps not only with duplicate pages inside our
/// site, but also handles proxying mirrors, which - accidentally or not - would
/// otherwise compete to rank for the same content.
///
/// If a page doesn't have a canonical URL (because it is non-public, and/or
/// customized to the current user), the page should be marked as `noindex`:
/// "When Googlebot next crawls that page and sees the tag or header, Googlebot
/// will drop that page entirely from Google Search results, regardless of
/// whether other sites link to it."
/// https://developers.google.com/search/docs/advanced/crawling/block-indexing
void _validateCanonicalLink(Element head) {
  final canonicalLinks = head
      .querySelectorAll('link')
      .where((e) => e.attributes['rel'] == 'canonical')
      .toList();
  if (canonicalLinks.length > 1) {
    throw ArgumentError('More than one canonical link was specified.');
  }
  if (canonicalLinks.isEmpty) {
    final robotsValues = head
        .querySelectorAll('meta')
        .where((elem) => elem.attributes['name'] == 'robots')
        .map((elem) => elem.attributes['content'])
        .expand((v) => v.split(' '))
        .toSet();
    if (!robotsValues.contains('noindex')) {
      throw ArgumentError(
          'When canonical URL is missing, noindex must be set.');
    }
  }
  if (canonicalLinks.length == 1) {
    final link = canonicalLinks.single;
    final href = link.attributes['href'];
    if (!href.startsWith('https://pub.dev/')) {
      throw ArgumentError(
          'Canonical URL must start with https://pub.dev/, found: $href.');
    }
    final uri = Uri.parse(href);
    if (uri.pathSegments.contains('.') || uri.pathSegments.contains('..')) {
      throw ArgumentError(
          'Canonical URL must not contain /./ or /../, found: $href.');
    }
  }
}
