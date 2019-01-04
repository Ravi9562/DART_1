// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

part 'pub_dartdoc_data.g.dart';

@JsonSerializable()
class PubDartdocData {
  final List<ApiElement> apiElements;

  PubDartdocData({
    @required this.apiElements,
  });

  factory PubDartdocData.fromJson(Map<String, dynamic> json) =>
      _$PubDartdocDataFromJson(json);

  Map<String, dynamic> toJson() => _$PubDartdocDataToJson(this);
}

@JsonSerializable(includeIfNull: false)
class ApiElement {
  /// The last part of the [qualifiedName].
  final String name;
  final String kind;
  final String parent;
  final String source;
  final String href;
  final String documentation;

  ApiElement({
    @required this.name,
    @required this.kind,
    @required this.parent,
    @required this.source,
    @required this.href,
    @required this.documentation,
  });

  factory ApiElement.fromJson(Map<String, dynamic> json) {
    // Previous data entries may contain the fully qualified name, we need to
    // transform them to the simple version.
    if (json.containsKey('name')) {
      json['name'] = (json['name'] as String).split('.').last;
    }
    return _$ApiElementFromJson(json);
  }

  Map<String, dynamic> toJson() => _$ApiElementToJson(this);

  String get qualifiedName => parent == null ? name : '$parent.$name';
}
