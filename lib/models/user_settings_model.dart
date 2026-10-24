import 'package:json_annotation/json_annotation.dart';

part 'user_settings_model.g.dart';

@JsonSerializable()
class UserSettingsModel {
  final String theme;
  final String language;
  @JsonKey(name: 'notificationsEnabled')
  final bool notifications;

  UserSettingsModel({
    this.theme = 'SYSTEM',
    this.language = 'vi',
    this.notifications = true,
  });

  factory UserSettingsModel.fromJson(Map<String, dynamic> json) =>
      _$UserSettingsModelFromJson(json);

  Map<String, dynamic> toJson() => _$UserSettingsModelToJson(this);

  UserSettingsModel copyWith({
    String? theme,
    String? language,
    bool? notifications,
  }) {
    return UserSettingsModel(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      notifications: notifications ?? this.notifications,
    );
  }
}
