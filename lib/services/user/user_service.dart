import '../../models/user_model.dart';
import '../../models/user_settings_model.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Service for user profile and settings management
class UserService {
  static UserService? _instance;
  final ApiClient _apiClient;

  UserService._() : _apiClient = ApiClient.instance;

  static UserService get instance {
    _instance ??= UserService._();
    return _instance!;
  }

  /// Get current user profile
  Future<void> deleteAccount() async {
    await _apiClient.delete('/users/account');
  }

  /// Get current user profile
  Future<UserModel> getProfile() async {
    try {
      final response = await _apiClient.get('/users/profile');

      if (response['success'] == true && response['data'] != null) {
        return UserModel.fromJson(response['data']['user']);
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Update user profile
  Future<UserModel> updateProfile({
    String? displayName,
    String? avatarUrl,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (displayName != null) body['displayName'] = displayName;
      if (avatarUrl != null) body['avatarUrl'] = avatarUrl;

      final response = await _apiClient.patch(
        '/users/profile',
        body: body,
      );

      if (response['success'] == true && response['data'] != null) {
        return UserModel.fromJson(response['data']['user']);
      }

      throw ApiException(message: 'Failed to update profile');
    } catch (e) {
      rethrow;
    }
  }

  /// Get user settings
  Future<UserSettingsModel> getSettings() async {
    try {
      final response = await _apiClient.get('/users/settings');

      if (response['success'] == true && response['data'] != null) {
        return UserSettingsModel.fromJson(response['data']['settings']);
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Update user settings
  Future<UserSettingsModel> updateSettings({
    String? theme,
    String? language,
    bool? notifications,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (theme != null) body['theme'] = theme;
      if (language != null) body['language'] = language;
      if (notifications != null) body['notifications'] = notifications;

      final response = await _apiClient.patch(
        '/users/settings',
        body: body,
      );

      if (response['success'] == true && response['data'] != null) {
        return UserSettingsModel.fromJson(response['data']['settings']);
      }

      throw ApiException(message: 'Failed to update settings');
    } catch (e) {
      rethrow;
    }
  }
}
