// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

final _attributeEscape = HtmlEscape(HtmlEscapeMode.attribute);
final _attributeRegExp = RegExp(r'^[a-z](?:[a-z0-9\-\_]*[a-z0-9]+)?$');
final _elementRegExp = _attributeRegExp;

/// The DOM context to use while constructing nodes.
///
/// Override this in browser.
DomContext dom = _StringDomContext();

/// Opaque entity for DOM nodes.
abstract class Node {}

/// Factory class to create DOM [Node]s.
abstract class DomContext {
  /// Creates a DOM fragment from the list of [children] nodes.
  Node fragment(Iterable<Node> children);

  /// Creates a DOM Element.
  Node element(
    String tag, {
    String? id,
    Iterable<String>? classes,
    Map<String, String>? attributes,
    Iterable<Node>? children,
  });

  /// Creates a DOM Text node.
  Node text(String value);

  /// Creates a DOM node with raw unsafe HTML content.
  Node rawUnsafeHtml(String value);
}

void _verifyElementTag(String tag) {
  if (_elementRegExp.matchAsPrefix(tag) == null) {
    throw FormatException('Invalid element tag "$tag".');
  }
}

void _verifyAttributeKeys(Iterable<String>? keys) {
  if (keys == null) return;
  for (final key in keys) {
    if (_attributeRegExp.matchAsPrefix(key) == null) {
      throw FormatException('Invalid attribute key "$key".');
    }
  }
}

/// Creates a DOM fragment from the list of [children] nodes using the default [DomContext].
Node fragment(Iterable<Node> children) => dom.fragment(children);

/// Creates a DOM Element using the default [DomContext].
Node element(
  String tag, {
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      tag,
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates a DOM Text node using the default [DomContext].
Node text(String value) => dom.text(value);

/// Creates a DOM node with raw unsafe HTML content using the default [DomContext].
Node rawUnsafeHtml(String value) => dom.rawUnsafeHtml(value);

/// Creates an `<a>` Element using the default [DomContext].
Node a({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
  String? href,
  String? rel,
  String? title,
}) {
  final hasAttributes =
      attributes != null || href != null || rel != null || title != null;
  return dom.element(
    'a',
    id: id,
    classes: classes,
    attributes: hasAttributes
        ? <String, String>{
            if (href != null) 'href': href,
            if (rel != null) 'rel': rel,
            if (title != null) 'title': title,
            if (attributes != null) ...attributes,
          }
        : null,
    children: children,
  );
}

/// Creates a `<code>` Element using the default [DomContext].
Node code({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'code',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates a `<div>` Element using the default [DomContext].
Node div({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'div',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates an `<img>` Element using the default [DomContext].
Node img({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
  String? src,
  String? title,
}) {
  final hasAttributes = attributes != null || src != null || title != null;
  return dom.element(
    'img',
    id: id,
    classes: classes,
    attributes: hasAttributes
        ? <String, String>{
            if (src != null) 'src': src,
            if (title != null) 'title': title,
            if (attributes != null) ...attributes,
          }
        : null,
    children: children,
  );
}

/// Creates a `<li>` Element using the default [DomContext].
Node li({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'li',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates a `<p>` Element using the default [DomContext].
Node p({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'p',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates a `<span>` Element using the default [DomContext].
Node span({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'span',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates a `<table>` Element using the default [DomContext].
Node table({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? head,
  Iterable<Node>? body,
}) =>
    dom.element(
      'table',
      id: id,
      classes: classes,
      attributes: attributes,
      children: [
        if (head != null) dom.element('thead', children: head),
        if (body != null) dom.element('tbody', children: body),
      ],
    );

/// Creates a `<td>` Element using the default [DomContext].
Node td({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'td',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates a `<th>` Element using the default [DomContext].
Node th({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'td',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates a `<tr>` Element using the default [DomContext].
Node tr({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'tr',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Creates a `<ul>` Element using the default [DomContext].
Node ul({
  String? id,
  Iterable<String>? classes,
  Map<String, String>? attributes,
  Iterable<Node>? children,
}) =>
    dom.element(
      'ul',
      id: id,
      classes: classes,
      attributes: attributes,
      children: children,
    );

/// Uses DOM nodes to emit escaped HTML string.
class _StringDomContext extends DomContext {
  @override
  Node fragment(Iterable<Node> children) => _StringNodeList(children);

  @override
  Node element(
    String tag, {
    String? id,
    Iterable<String>? classes,
    Map<String, String>? attributes,
    Iterable<Node>? children,
  }) {
    _verifyElementTag(tag);
    _verifyAttributeKeys(attributes?.keys);
    return _StringElement(
        tag, _mergeAttributes(id, classes, attributes), children);
  }

  @override
  Node text(String value) => _StringText(value);

  @override
  Node rawUnsafeHtml(String value) => _StringRawUnsafeHtml(value);
}

Map<String, String>? _mergeAttributes(
    String? id, Iterable<String>? classes, Map<String, String>? attributes) {
  final hasClasses = classes != null && classes.isNotEmpty;
  final hasAttributes =
      id != null || hasClasses || (attributes != null && attributes.isNotEmpty);
  if (!hasAttributes) return null;
  return <String, String>{
    if (id != null) 'id': id,
    if (classes != null && classes.isNotEmpty) 'class': classes.join(' '),
    if (attributes != null) ...attributes,
  };
}

abstract class _StringNode extends Node {
  void writeHtml(StringSink sink);

  @override
  String toString() {
    final sb = StringBuffer();
    writeHtml(sb);
    return sb.toString();
  }
}

class _StringNodeList extends _StringNode {
  final List<_StringNode> _children;

  _StringNodeList(Iterable<Node> children)
      : _children = children.cast<_StringNode>().toList();

  @override
  void writeHtml(StringSink sink) {
    for (final node in _children) {
      node.writeHtml(sink);
    }
  }
}

class _StringElement extends _StringNode {
  static const _selfClosing = <String>{
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'param',
    'source',
    'track',
    'wbr',
  };

  final String _tag;
  final Map<String, String>? _attributes;
  final List<_StringNode>? _children;

  _StringElement(this._tag, this._attributes, Iterable<Node>? children)
      : _children = children?.cast<_StringNode>().toList();

  @override
  void writeHtml(StringSink sink) {
    sink.write('<$_tag');
    if (_attributes != null) {
      for (final e in _attributes!.entries) {
        sink.write(' ${e.key}="${_attributeEscape.convert(e.value)}"');
      }
    }
    final hasChildren = _children != null && _children!.isNotEmpty;
    if (hasChildren) {
      sink.write('>');
      for (final child in _children!) {
        child.writeHtml(sink);
      }
      sink.write('</$_tag>');
    } else if (_selfClosing.contains(_tag)) {
      sink.write('/>');
    } else {
      sink.write('></$_tag>');
    }
  }
}

class _StringText extends _StringNode {
  final String _value;

  _StringText(this._value);

  @override
  void writeHtml(StringSink sink) {
    sink.write(htmlEscape.convert(_value));
  }
}

class _StringRawUnsafeHtml extends _StringNode {
  final String _value;

  _StringRawUnsafeHtml(this._value);

  @override
  void writeHtml(StringSink sink) {
    sink.write(_value);
  }
}
