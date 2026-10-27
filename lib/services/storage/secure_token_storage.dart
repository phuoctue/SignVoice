import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_config.dart';
import 'token_store.dart';

/// Native tokens use secure storage; browsers keep access tokens in memory
/// and send the refresh token in a server-issued HttpOnly cookie.
class SecureTokenStorage implements TokenStore {
  SecureTokenStorage({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );
  static final instance = SecureTokenStorage();
  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;
  String? _webAccessToken;
  String? _nativeAccessToken;
  bool _accessLoaded = false;
  int _generation = 0;
  Future<String?>? _accessRead;
  Future<void>? _initializing;

  Future<void> init() => _initializing ??= _init().catchError((Object error) {
    _initializing = null;
    throw error;
  });

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    // Remove tokens written by the old, unencrypted implementation.
    await _prefs!.remove(ApiConfig.accessTokenKey);
    await _prefs!.remove(ApiConfig.refreshTokenKey);
  }

  Future<bool> saveAccessToken(String token) async {
    if (kIsWeb) {
      _webAccessToken = token;
    } else {
      await _secureStorage.write(key: ApiConfig.accessTokenKey, value: token);
      _generation++;
      _nativeAccessToken = token;
      _accessLoaded = true;
      _accessRead = null;
    }
    return true;
  }

  @override
  Future<String?> getAccessToken() async {
    await init();
    if (kIsWeb) return _webAccessToken;
    while (!_accessLoaded) {
      final generation = _generation;
      final read = _accessRead ??= _secureStorage.read(
        key: ApiConfig.accessTokenKey,
      );
      try {
        final value = await read;
        if (generation != _generation) continue;
        _nativeAccessToken = value;
        _accessLoaded = true;
      } catch (_) {
        if (generation != _generation) continue;
        rethrow;
      } finally {
        if (identical(_accessRead, read)) _accessRead = null;
      }
    }
    return _nativeAccessToken;
  }

  Future<bool> saveRefreshToken(String token) async {
    if (!kIsWeb) {
      await _secureStorage.write(key: ApiConfig.refreshTokenKey, value: token);
    }
    return true;
  }

  @override
  Future<String?> getRefreshToken() async {
    await init();
    return kIsWeb ? null : _secureStorage.read(key: ApiConfig.refreshTokenKey);
  }

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await init();
    await saveRefreshToken(refreshToken);
    await saveAccessToken(accessToken);
  }

  @override
  Future<void> saveUserInfo({
    required String userId,
    required String role,
  }) async {
    await init();
    await _prefs!.setString(ApiConfig.userIdKey, userId);
    await _prefs!.setString(ApiConfig.userRoleKey, role);
  }

  @override
  Future<String?> getUserRole() async {
    await init();
    return _prefs!.getString(ApiConfig.userRoleKey);
  }

  Future<String?> getUserId() async {
    await init();
    return _prefs!.getString(ApiConfig.userIdKey);
  }

  @override
  Future<bool> isAuthenticated() async =>
      (await getAccessToken())?.isNotEmpty == true;

  Future<void> clearTokens() async {
    _webAccessToken = null;
    _generation++;
    _nativeAccessToken = null;
    _accessLoaded = true;
    _accessRead = null;
    if (!kIsWeb) {
      await Future.wait([
        _secureStorage.delete(key: ApiConfig.accessTokenKey),
        _secureStorage.delete(key: ApiConfig.refreshTokenKey),
      ]);
    }
  }

  @override
  Future<void> clearAll() async {
    await clearTokens();
    await init();
    await _prefs!.remove(ApiConfig.userIdKey);
    await _prefs!.remove(ApiConfig.userRoleKey);
  }
}
