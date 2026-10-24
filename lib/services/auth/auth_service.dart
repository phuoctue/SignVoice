import '../api/api_client.dart';
import '../api/api_config.dart';
import '../storage/secure_token_storage.dart';
import '../../models/user_model.dart';
import '../storage/token_store.dart';
import '../api/api_exception.dart';
import 'guest_device_identity.dart';
import 'guest_trial_access.dart';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Authentication service
class AuthService {
  static AuthService? _instance;
  final ApiClient _apiClient;
  final TokenStore _tokenStorage;

  AuthService({ApiClient? apiClient, TokenStore? tokenStorage})
    : _apiClient = apiClient ?? ApiClient.instance,
      _tokenStorage = tokenStorage ?? SecureTokenStorage.instance;

  ValueListenable<int> get sessionInvalidated => _apiClient.sessionInvalidated;

  Future<Map<String, bool>> oauthProviders() async {
    final response = await _apiClient.get(
      '/auth/oauth/providers',
      requiresAuth: false,
    );
    final data = response['data'];
    if (data is! Map || data['google'] is! bool || data['facebook'] is! bool) {
      throw const FormatException('Invalid OAuth provider response');
    }
    return {
      'google': data['google'] as bool,
      'facebook': data['facebook'] as bool,
    };
  }

  Future<void> startOAuth(String provider) async {
    if (!kIsWeb) {
      throw UnsupportedError(
        'OAuth hiện hỗ trợ trình duyệt web. Hãy dùng email trên ứng dụng.',
      );
    }
    if (!const ['google', 'facebook'].contains(provider)) {
      throw ArgumentError('Unknown OAuth provider');
    }
    final url = Uri.base.resolve(
      '${ApiConfig.baseUrl}/auth/oauth/$provider/start',
    );
    if (!await launchUrl(url, webOnlyWindowName: '_self')) {
      throw StateError('Không mở được trang đăng nhập.');
    }
  }

  Future<UserModel> completeOAuth() async {
    final epoch = _apiClient.beginAuthentication();
    final response = await _apiClient.post(
      '/auth/oauth/complete',
      requiresAuth: false,
    );
    return _saveAuthResponse(response, epoch);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final epoch = _apiClient.sessionEpoch;
    await _apiClient.post(
      '/auth/change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    await _apiClient.clearSession(expectedEpoch: epoch);
  }

  Future<UserModel?> restoreSession() async {
    if (!await _tokenStorage.isAuthenticated()) {
      // Metadata permits attempting cookie refresh; authorization comes from /me.
      // Its absence also records an intentional logout, including while offline.
      if (_apiClient.useRefreshCookie &&
          await _tokenStorage.getUserRole() == null) {
        return null;
      }
      if (!_apiClient.useRefreshCookie &&
          await _tokenStorage.getRefreshToken() == null) {
        return null;
      }
      await _apiClient.refreshToken();
    }
    return getCurrentUser();
  }

  Future<UserModel> _saveAuthResponse(dynamic response, int epoch) async {
    _apiClient.checkSession(epoch);
    final data = response['data'];
    final user = UserModel.fromJson(Map<String, dynamic>.from(data['user']));
    final tokens = data['tokens'];
    await _apiClient.writeSession(epoch, () async {
      await _tokenStorage.saveTokens(
        accessToken: tokens['accessToken'],
        refreshToken: tokens['refreshToken'],
      );
      await _tokenStorage.saveUserInfo(userId: user.id, role: user.roleName);
    });
    _apiClient.sessionStarted(expectedEpoch: epoch);
    return user;
  }

  static AuthService get instance {
    _instance ??= AuthService();
    return _instance!;
  }

  /// Register new user
  Future<UserModel> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final epoch = _apiClient.beginAuthentication();
    final response = await _apiClient.post(
      '${ApiConfig.authEndpoint}/register',
      body: {'email': email, 'password': password, 'displayName': displayName},
      requiresAuth: false,
    );

    if (response['success'] == true && response['data'] != null) {
      return _saveAuthResponse(response, epoch);
    }

    throw Exception('Registration failed');
  }

  /// Login with email and password
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final epoch = _apiClient.beginAuthentication();
    final response = await _apiClient.post(
      '${ApiConfig.authEndpoint}/login',
      body: {'email': email, 'password': password},
      requiresAuth: false,
    );

    if (response['success'] == true && response['data'] != null) {
      return _saveAuthResponse(response, epoch);
    }

    throw Exception('Login failed');
  }

  /// Login as guest
  Future<void> requestPasswordReset(String email) async {
    await _apiClient.post(
      '${ApiConfig.authEndpoint}/forgot-password',
      body: {'email': email.trim()},
      requiresAuth: false,
    );
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _apiClient.post(
      '${ApiConfig.authEndpoint}/reset-password',
      body: {'token': token, 'newPassword': newPassword},
      requiresAuth: false,
    );
    await _tokenStorage.clearAll();
    _apiClient.sessionInvalidated.value++;
  }

  /// Login as guest
  Future<UserModel> loginAsGuest() async {
    final epoch = _apiClient.beginAuthentication();
    final response = await _apiClient.post(
      '${ApiConfig.authEndpoint}/guest',
      body: {'deviceKey': await guestDeviceKey()},
      requiresAuth: false,
    );

    if (response['success'] == true && response['data'] != null) {
      return _saveAuthResponse(response, epoch);
    }

    throw Exception('Guest login failed');
  }

  Future<GuestTrialAccess> guestTrial({bool start = false}) async {
    final key = await guestDeviceKey();
    final response = start
        ? await _apiClient.post('/guest-trial/start', body: {'deviceKey': key})
        : await _apiClient.get(
            '/guest-trial/status',
            queryParameters: {'deviceKey': key},
          );
    return GuestTrialAccess.fromJson(
      Map<String, dynamic>.from(response['data'] as Map),
    );
  }

  /// Convert guest to permanent account
  Future<UserModel> convertGuest({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final epoch = _apiClient.beginAuthentication();
    final response = await _apiClient.post(
      '${ApiConfig.authEndpoint}/convert-guest',
      body: {'email': email, 'password': password, 'displayName': displayName},
      requiresAuth: true,
    );

    if (response['success'] == true && response['data'] != null) {
      return _saveAuthResponse(response, epoch);
    }

    throw Exception('Guest conversion failed');
  }

  /// Get current user
  Future<UserModel> getCurrentUser() async {
    final response = await _apiClient.get(
      '${ApiConfig.authEndpoint}/me',
      requiresAuth: true,
    );

    if (response['success'] == true && response['data'] != null) {
      return UserModel.fromJson(response['data']);
    }

    throw Exception('Failed to get current user');
  }

  /// Logout
  Future<void> logout() async {
    try {
      await _apiClient.logout();
    } finally {
      // Clear tokens even if request fails
      await _tokenStorage.clearAll();
    }
  }

  /// Logout from all devices
  Future<void> logoutAll() async {
    try {
      await _apiClient.logout(allDevices: true);
    } finally {
      await _tokenStorage.clearAll();
    }
  }

  /// Refresh access token
  Future<void> refreshToken() async {
    await _apiClient.refreshToken();
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    return _tokenStorage.isAuthenticated();
  }

  /// Get user role
  Future<String?> getUserRole() async {
    return _tokenStorage.getUserRole();
  }

  /// Check if user has specific role
  Future<bool> hasRole(String role) async {
    try {
      return (await getCurrentUser()).roleName == role;
    } on ApiException {
      return false;
    }
  }

  /// Check if user is admin
  Future<bool> isAdmin() async {
    return hasRole('ADMIN');
  }

  /// Check if user is staff (staff or admin)
  Future<bool> isStaff() async {
    return (await getCurrentUser()).isStaff;
  }
}
