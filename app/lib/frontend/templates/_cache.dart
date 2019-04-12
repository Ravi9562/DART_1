// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:mustache/mustache.dart' as mustache;
import 'package:path/path.dart' as path;

import '../request_context.dart';
import '../static_files.dart' show resolveAppDir;

final templateCache = TemplateCache();

/// Loads, parses, caches and renders mustache templates.
class TemplateCache {
  /// A cache which keeps all used mustache templates parsed in memory.
  final Map<String, mustache.Template> _parsedMustacheTemplates = {};

  TemplateCache() {
    _loadDirectory(path.join(resolveAppDir(), 'lib/frontend/templates/views'));
  }

  void _loadDirectory(String templateFolder) {
    Directory(templateFolder)
        .listSync(recursive: true)
        .where((fse) => fse is File)
        .cast<File>()
        .where((f) => f.path.endsWith('.mustache'))
        .forEach(
      (file) {
        final t = mustache.Template(file.readAsStringSync(), lenient: true);
        final relativePath = path.relative(file.path, from: templateFolder);
        final name = path.withoutExtension(relativePath);
        _parsedMustacheTemplates[name] = t;
      },
    );
  }

  /// Renders [template] with given [values].
  String renderTemplate(String template, values) {
    mustache.Template parsedTemplate;
    if (requestContext.isExperimental) {
      final dirName = path.dirname(template);
      final expFileName = 'experimental_${path.basename(template)}';
      final expTemplate =
          dirName == '.' ? expFileName : path.join(dirName, expFileName);
      parsedTemplate = _parsedMustacheTemplates[expTemplate];
    }
    parsedTemplate ??= _parsedMustacheTemplates[template];
    if (parsedTemplate == null) {
      throw ArgumentError('Template $template was not found.');
    }
    return parsedTemplate.renderString(values);
  }
}
