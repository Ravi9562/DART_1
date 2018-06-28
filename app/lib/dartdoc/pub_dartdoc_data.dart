// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

part 'pub_dartdoc_data.g.dart';

@JsonSerializable()
class PubDartdocData extends Object with _$PubDartdocDataSerializerMixin {
  @override
  final List<ApiElement> apiElements;

  PubDartdocData({
    @required this.apiElements,
  });

  factory PubDartdocData.fromJson(Map<String, dynamic> json) =>
      _$PubDartdocDataFromJson(json);
}

@JsonSerializable()
class ApiElement extends Object with _$ApiElementSerializerMixin {
  @override
  final String name;

  @override
  final String kind;

  @JsonKey(includeIfNull: false)
  @override
  final String parent;

  @override
  final String source;

  @JsonKey(includeIfNull: false)
  @override
  final String href;

  @JsonKey(includeIfNull: false)
  @override
  final String documentation;

  ApiElement({
    @required this.name,
    @required this.kind,
    @required this.parent,
    @required this.source,
    @required this.href,
    @required this.documentation,
  });

  factory ApiElement.fromJson(Map<String, dynamic> json) =>
      _$ApiElementFromJson(json);
}
