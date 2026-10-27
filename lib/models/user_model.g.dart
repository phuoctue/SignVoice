// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserModel _$UserModelFromJson(Map<String, dynamic> json) => UserModel(
  id: json['_id'] as String,
  email: json['email'] as String?,
  displayName: json['displayName'] as String,
  avatarUrl: json['avatarUrl'] as String?,
  accountType: $enumDecode(_$AccountTypeEnumMap, json['accountType']),
  role: $enumDecode(_$UserRoleEnumMap, json['role']),
  customRoleId: json['customRoleId'] as String?,
  customRoleName: json['customRoleName'] as String?,
  permissions:
      (json['permissions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  status: $enumDecode(_$AccountStatusEnumMap, json['status']),
  isGuest: json['isGuest'] as bool,
  googleLinked: json['googleLinked'] as bool? ?? false,
  guestConvertedAt: json['guestConvertedAt'] == null
      ? null
      : DateTime.parse(json['guestConvertedAt'] as String),
  lastLoginAt: json['lastLoginAt'] == null
      ? null
      : DateTime.parse(json['lastLoginAt'] as String),
  lastLoginIp: json['lastLoginIp'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$UserModelToJson(UserModel instance) => <String, dynamic>{
  '_id': instance.id,
  'email': instance.email,
  'displayName': instance.displayName,
  'avatarUrl': instance.avatarUrl,
  'accountType': _$AccountTypeEnumMap[instance.accountType]!,
  'role': _$UserRoleEnumMap[instance.role]!,
  'customRoleId': instance.customRoleId,
  'customRoleName': instance.customRoleName,
  'permissions': instance.permissions,
  'status': _$AccountStatusEnumMap[instance.status]!,
  'isGuest': instance.isGuest,
  'googleLinked': instance.googleLinked,
  'guestConvertedAt': instance.guestConvertedAt?.toIso8601String(),
  'lastLoginAt': instance.lastLoginAt?.toIso8601String(),
  'lastLoginIp': instance.lastLoginIp,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};

const _$AccountTypeEnumMap = {
  AccountType.local: 'LOCAL',
  AccountType.google: 'GOOGLE',
  AccountType.facebook: 'FACEBOOK',
  AccountType.guest: 'GUEST',
};

const _$UserRoleEnumMap = {
  UserRole.user: 'USER',
  UserRole.staff: 'STAFF',
  UserRole.admin: 'ADMIN',
};

const _$AccountStatusEnumMap = {
  AccountStatus.active: 'ACTIVE',
  AccountStatus.suspended: 'SUSPENDED',
  AccountStatus.deleted: 'DELETED',
};
