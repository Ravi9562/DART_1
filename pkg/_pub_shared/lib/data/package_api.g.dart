// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'package_api.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UploadInfo _$UploadInfoFromJson(Map<String, dynamic> json) => UploadInfo(
      url: json['url'] as String,
      fields: (json['fields'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
    );

Map<String, dynamic> _$UploadInfoToJson(UploadInfo instance) =>
    <String, dynamic>{
      'url': instance.url,
      'fields': instance.fields,
    };

PkgOptions _$PkgOptionsFromJson(Map<String, dynamic> json) => PkgOptions(
      isDiscontinued: json['isDiscontinued'] as bool?,
      replacedBy: json['replacedBy'] as String?,
      isUnlisted: json['isUnlisted'] as bool?,
    );

Map<String, dynamic> _$PkgOptionsToJson(PkgOptions instance) =>
    <String, dynamic>{
      'isDiscontinued': instance.isDiscontinued,
      'replacedBy': instance.replacedBy,
      'isUnlisted': instance.isUnlisted,
    };

VersionOptions _$VersionOptionsFromJson(Map<String, dynamic> json) =>
    VersionOptions(
      isRetracted: json['isRetracted'] as bool?,
    );

Map<String, dynamic> _$VersionOptionsToJson(VersionOptions instance) =>
    <String, dynamic>{
      'isRetracted': instance.isRetracted,
    };

PackagePublisherInfo _$PackagePublisherInfoFromJson(
        Map<String, dynamic> json) =>
    PackagePublisherInfo(
      publisherId: json['publisherId'] as String?,
    );

Map<String, dynamic> _$PackagePublisherInfoToJson(
        PackagePublisherInfo instance) =>
    <String, dynamic>{
      'publisherId': instance.publisherId,
    };

SuccessMessage _$SuccessMessageFromJson(Map<String, dynamic> json) =>
    SuccessMessage(
      success: Message.fromJson(json['success'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SuccessMessageToJson(SuccessMessage instance) =>
    <String, dynamic>{
      'success': instance.success,
    };

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
      message: json['message'] as String,
    );

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
      'message': instance.message,
    };

PackageData _$PackageDataFromJson(Map<String, dynamic> json) => PackageData(
      name: json['name'] as String,
      isDiscontinued: json['isDiscontinued'] as bool?,
      replacedBy: json['replacedBy'] as String?,
      latest: VersionInfo.fromJson(json['latest'] as Map<String, dynamic>),
      versions: (json['versions'] as List<dynamic>)
          .map((e) => VersionInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PackageDataToJson(PackageData instance) {
  final val = <String, dynamic>{
    'name': instance.name,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('isDiscontinued', instance.isDiscontinued);
  writeNotNull('replacedBy', instance.replacedBy);
  val['latest'] = instance.latest;
  val['versions'] = instance.versions;
  return val;
}

VersionInfo _$VersionInfoFromJson(Map<String, dynamic> json) => VersionInfo(
      version: json['version'] as String,
      retracted: json['retracted'] as bool?,
      pubspec: json['pubspec'] as Map<String, dynamic>,
      archiveUrl: json['archive_url'] as String?,
      published: json['published'] == null
          ? null
          : DateTime.parse(json['published'] as String),
    );

Map<String, dynamic> _$VersionInfoToJson(VersionInfo instance) {
  final val = <String, dynamic>{
    'version': instance.version,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('retracted', instance.retracted);
  val['pubspec'] = instance.pubspec;
  writeNotNull('archive_url', instance.archiveUrl);
  writeNotNull('published', instance.published?.toIso8601String());
  return val;
}

VersionScore _$VersionScoreFromJson(Map<String, dynamic> json) => VersionScore(
      grantedPoints: json['grantedPoints'] as int?,
      maxPoints: json['maxPoints'] as int?,
      likeCount: json['likeCount'] as int?,
      popularityScore: (json['popularityScore'] as num?)?.toDouble(),
      lastUpdated: json['lastUpdated'] == null
          ? null
          : DateTime.parse(json['lastUpdated'] as String),
    );

Map<String, dynamic> _$VersionScoreToJson(VersionScore instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('grantedPoints', instance.grantedPoints);
  writeNotNull('maxPoints', instance.maxPoints);
  writeNotNull('likeCount', instance.likeCount);
  writeNotNull('popularityScore', instance.popularityScore);
  writeNotNull('lastUpdated', instance.lastUpdated?.toIso8601String());
  return val;
}

InviteUploaderRequest _$InviteUploaderRequestFromJson(
        Map<String, dynamic> json) =>
    InviteUploaderRequest(
      email: json['email'] as String,
    );

Map<String, dynamic> _$InviteUploaderRequestToJson(
        InviteUploaderRequest instance) =>
    <String, dynamic>{
      'email': instance.email,
    };
