// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'configuration.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Configuration _$ConfigurationFromJson(Map json) => $checkedCreate(
      'Configuration',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          allowedKeys: const [
            'packageBucketName',
            'imageBucketName',
            'projectId',
            'searchServicePrefix',
            'dartdocStorageBucketName',
            'popularityDumpBucketName',
            'searchSnapshotBucketName',
            'storageBaseUrl',
            'pubClientAudience',
            'pubSiteAudience',
            'adminAudience',
            'gmailRelayServiceAccount',
            'gmailRelayImpersonatedGSuiteUser',
            'uploadSignerServiceAccount',
            'blockRobots',
            'productionHosts',
            'primaryApiUri',
            'primarySiteUri',
            'admins'
          ],
        );
        final val = Configuration(
          projectId: $checkedConvert('projectId', (v) => v as String),
          packageBucketName:
              $checkedConvert('packageBucketName', (v) => v as String?),
          imageBucketName:
              $checkedConvert('imageBucketName', (v) => v as String?),
          dartdocStorageBucketName:
              $checkedConvert('dartdocStorageBucketName', (v) => v as String?),
          popularityDumpBucketName:
              $checkedConvert('popularityDumpBucketName', (v) => v as String?),
          searchSnapshotBucketName:
              $checkedConvert('searchSnapshotBucketName', (v) => v as String?),
          searchServicePrefix:
              $checkedConvert('searchServicePrefix', (v) => v as String),
          storageBaseUrl:
              $checkedConvert('storageBaseUrl', (v) => v as String?),
          pubClientAudience:
              $checkedConvert('pubClientAudience', (v) => v as String?),
          pubSiteAudience:
              $checkedConvert('pubSiteAudience', (v) => v as String?),
          adminAudience: $checkedConvert('adminAudience', (v) => v as String?),
          gmailRelayServiceAccount:
              $checkedConvert('gmailRelayServiceAccount', (v) => v as String?),
          gmailRelayImpersonatedGSuiteUser: $checkedConvert(
              'gmailRelayImpersonatedGSuiteUser', (v) => v as String?),
          uploadSignerServiceAccount: $checkedConvert(
              'uploadSignerServiceAccount', (v) => v as String?),
          blockRobots: $checkedConvert('blockRobots', (v) => v as bool),
          productionHosts: $checkedConvert('productionHosts',
              (v) => (v as List<dynamic>?)?.map((e) => e as String).toList()),
          primaryApiUri: $checkedConvert('primaryApiUri',
              (v) => v == null ? null : Uri.parse(v as String)),
          primarySiteUri:
              $checkedConvert('primarySiteUri', (v) => Uri.parse(v as String)),
          admins: $checkedConvert(
              'admins',
              (v) => (v as List<dynamic>?)
                  ?.map((e) =>
                      AdminId.fromJson(Map<String, dynamic>.from(e as Map)))
                  .toList()),
        );
        return val;
      },
    );

Map<String, dynamic> _$ConfigurationToJson(Configuration instance) =>
    <String, dynamic>{
      'packageBucketName': instance.packageBucketName,
      'imageBucketName': instance.imageBucketName,
      'projectId': instance.projectId,
      'searchServicePrefix': instance.searchServicePrefix,
      'dartdocStorageBucketName': instance.dartdocStorageBucketName,
      'popularityDumpBucketName': instance.popularityDumpBucketName,
      'searchSnapshotBucketName': instance.searchSnapshotBucketName,
      'storageBaseUrl': instance.storageBaseUrl,
      'pubClientAudience': instance.pubClientAudience,
      'pubSiteAudience': instance.pubSiteAudience,
      'adminAudience': instance.adminAudience,
      'gmailRelayServiceAccount': instance.gmailRelayServiceAccount,
      'gmailRelayImpersonatedGSuiteUser':
          instance.gmailRelayImpersonatedGSuiteUser,
      'uploadSignerServiceAccount': instance.uploadSignerServiceAccount,
      'blockRobots': instance.blockRobots,
      'productionHosts': instance.productionHosts,
      'primaryApiUri': instance.primaryApiUri?.toString(),
      'primarySiteUri': instance.primarySiteUri.toString(),
      'admins': instance.admins?.map((e) => e.toJson()).toList(),
    };

AdminId _$AdminIdFromJson(Map json) => $checkedCreate(
      'AdminId',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          allowedKeys: const ['oauthUserId', 'email', 'permissions'],
        );
        final val = AdminId(
          oauthUserId: $checkedConvert('oauthUserId', (v) => v as String?),
          email: $checkedConvert('email', (v) => v as String?),
          permissions: $checkedConvert(
              'permissions',
              (v) => (v as List<dynamic>).map(
                  (e) => $enumDecodeNullable(_$AdminPermissionEnumMap, e))),
        );
        return val;
      },
    );

Map<String, dynamic> _$AdminIdToJson(AdminId instance) => <String, dynamic>{
      'oauthUserId': instance.oauthUserId,
      'email': instance.email,
      'permissions':
          instance.permissions.map((e) => _$AdminPermissionEnumMap[e]).toList(),
    };

const _$AdminPermissionEnumMap = {
  AdminPermission.executeTool: 'executeTool',
  AdminPermission.listUsers: 'listUsers',
  AdminPermission.manageAssignedTags: 'manageAssignedTags',
  AdminPermission.managePackageOwnership: 'managePackageOwnership',
  AdminPermission.manageRetraction: 'manageRetraction',
  AdminPermission.removePackage: 'removePackage',
  AdminPermission.removeUsers: 'removeUsers',
};
