// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_settings_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserSettingsModel _$UserSettingsModelFromJson(Map<String, dynamic> json) =>
    UserSettingsModel(
      theme: json['theme'] as String? ?? 'SYSTEM',
      language: json['language'] as String? ?? 'vi',
      notifications: json['notificationsEnabled'] as bool? ?? true,
    );

Map<String, dynamic> _$UserSettingsModelToJson(UserSettingsModel instance) =>
    <String, dynamic>{
      'theme': instance.theme,
      'language': instance.language,
      'notificationsEnabled': instance.notifications,
    };
