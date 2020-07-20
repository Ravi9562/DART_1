// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScoreCardData _$ScoreCardDataFromJson(Map<String, dynamic> json) {
  return ScoreCardData(
    packageName: json['packageName'] as String,
    packageVersion: json['packageVersion'] as String,
    runtimeVersion: json['runtimeVersion'] as String,
    updated: json['updated'] == null
        ? null
        : DateTime.parse(json['updated'] as String),
    packageCreated: json['packageCreated'] == null
        ? null
        : DateTime.parse(json['packageCreated'] as String),
    packageVersionCreated: json['packageVersionCreated'] == null
        ? null
        : DateTime.parse(json['packageVersionCreated'] as String),
    grantedPubPoints: json['grantedPubPoints'] as int,
    maxPubPoints: json['maxPubPoints'] as int,
    popularityScore: (json['popularityScore'] as num)?.toDouble(),
    derivedTags:
        (json['derivedTags'] as List)?.map((e) => e as String)?.toList(),
    flags: (json['flags'] as List)?.map((e) => e as String)?.toList(),
    reportTypes:
        (json['reportTypes'] as List)?.map((e) => e as String)?.toList(),
  );
}

Map<String, dynamic> _$ScoreCardDataToJson(ScoreCardData instance) =>
    <String, dynamic>{
      'packageName': instance.packageName,
      'packageVersion': instance.packageVersion,
      'runtimeVersion': instance.runtimeVersion,
      'updated': instance.updated?.toIso8601String(),
      'packageCreated': instance.packageCreated?.toIso8601String(),
      'packageVersionCreated':
          instance.packageVersionCreated?.toIso8601String(),
      'grantedPubPoints': instance.grantedPubPoints,
      'maxPubPoints': instance.maxPubPoints,
      'popularityScore': instance.popularityScore,
      'derivedTags': instance.derivedTags,
      'flags': instance.flags,
      'reportTypes': instance.reportTypes,
    };

PanaReport _$PanaReportFromJson(Map<String, dynamic> json) {
  return PanaReport(
    timestamp: json['timestamp'] == null
        ? null
        : DateTime.parse(json['timestamp'] as String),
    panaRuntimeInfo: json['panaRuntimeInfo'] == null
        ? null
        : PanaRuntimeInfo.fromJson(
            json['panaRuntimeInfo'] as Map<String, dynamic>),
    reportStatus: json['reportStatus'] as String,
    derivedTags:
        (json['derivedTags'] as List)?.map((e) => e as String)?.toList(),
    pkgDependencies: (json['pkgDependencies'] as List)
        ?.map((e) => e == null
            ? null
            : PkgDependency.fromJson(e as Map<String, dynamic>))
        ?.toList(),
    licenses: (json['licenses'] as List)
        ?.map((e) =>
            e == null ? null : LicenseFile.fromJson(e as Map<String, dynamic>))
        ?.toList(),
    report: json['report'] == null
        ? null
        : Report.fromJson(json['report'] as Map<String, dynamic>),
    flags: (json['flags'] as List)?.map((e) => e as String)?.toList(),
  );
}

Map<String, dynamic> _$PanaReportToJson(PanaReport instance) {
  final val = <String, dynamic>{
    'timestamp': instance.timestamp?.toIso8601String(),
    'panaRuntimeInfo': instance.panaRuntimeInfo,
    'reportStatus': instance.reportStatus,
    'derivedTags': instance.derivedTags,
    'pkgDependencies': instance.pkgDependencies,
    'licenses': instance.licenses,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('report', instance.report);
  writeNotNull('flags', instance.flags);
  return val;
}

DartdocReport _$DartdocReportFromJson(Map<String, dynamic> json) {
  return DartdocReport(
    reportStatus: json['reportStatus'] as String,
    dartdocEntry: json['dartdocEntry'] == null
        ? null
        : DartdocEntry.fromJson(json['dartdocEntry'] as Map<String, dynamic>),
    documentationSection: json['documentationSection'] == null
        ? null
        : ReportSection.fromJson(
            json['documentationSection'] as Map<String, dynamic>),
  );
}

Map<String, dynamic> _$DartdocReportToJson(DartdocReport instance) =>
    <String, dynamic>{
      'reportStatus': instance.reportStatus,
      'dartdocEntry': instance.dartdocEntry,
      'documentationSection': instance.documentationSection,
    };
