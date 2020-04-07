// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'package_api.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UploadInfo _$UploadInfoFromJson(Map<String, dynamic> json) {
  return UploadInfo(
    url: json['url'] as String,
    fields: (json['fields'] as Map<String, dynamic>)?.map(
      (k, e) => MapEntry(k, e as String),
    ),
  );
}

Map<String, dynamic> _$UploadInfoToJson(UploadInfo instance) =>
    <String, dynamic>{
      'url': instance.url,
      'fields': instance.fields,
    };

PkgOptions _$PkgOptionsFromJson(Map<String, dynamic> json) {
  return PkgOptions(
    isDiscontinued: json['isDiscontinued'] as bool,
  );
}

Map<String, dynamic> _$PkgOptionsToJson(PkgOptions instance) =>
    <String, dynamic>{
      'isDiscontinued': instance.isDiscontinued,
    };

PackagePublisherInfo _$PackagePublisherInfoFromJson(Map<String, dynamic> json) {
  return PackagePublisherInfo(
    publisherId: json['publisherId'] as String,
  );
}

Map<String, dynamic> _$PackagePublisherInfoToJson(
        PackagePublisherInfo instance) =>
    <String, dynamic>{
      'publisherId': instance.publisherId,
    };

SuccessMessage _$SuccessMessageFromJson(Map<String, dynamic> json) {
  return SuccessMessage(
    success: json['success'] == null
        ? null
        : Message.fromJson(json['success'] as Map<String, dynamic>),
  );
}

Map<String, dynamic> _$SuccessMessageToJson(SuccessMessage instance) =>
    <String, dynamic>{
      'success': instance.success,
    };

Message _$MessageFromJson(Map<String, dynamic> json) {
  return Message(
    message: json['message'] as String,
  );
}

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
      'message': instance.message,
    };

VersionInfo _$VersionInfoFromJson(Map<String, dynamic> json) {
  return VersionInfo(
    version: json['version'] as String,
    pubspec: json['pubspec'] as Map<String, dynamic>,
    archiveUrl: json['archive_url'] as String,
  );
}

Map<String, dynamic> _$VersionInfoToJson(VersionInfo instance) =>
    <String, dynamic>{
      'version': instance.version,
      'pubspec': instance.pubspec,
      'archive_url': instance.archiveUrl,
    };
