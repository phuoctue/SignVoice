import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_exception.dart';
import '../storage/secure_token_storage.dart';
import '../storage/token_store.dart';
import 'http_client_factory.dart';

/// HTTP client with authentication and error handling
class ApiClient {
  static ApiClient? _instance;
  final http.Client _client;
  final TokenStore _tokenStorage;
  final bool useRefreshCookie;
  final ValueNotifier<int> sessionInvalidated = ValueNotifier(0);
  Future<void>? _refreshing;
  bool _loggingOut = false;
  int _sessionEpoch = 0;
  Future<void> _sessionWrites = Future<void>.value();
  int get sessionEpoch => _sessionEpoch;
  void checkSession(int epoch) {
    if (epoch != _sessionEpoch) {
      throw ApiException(
        message: 'Tài khoản đã thay đổi. Vui lòng thực hiện lại.',
        code: 'SESSION_CHANGED',
        statusCode: 409,
      );
    }
  }

  int beginAuthentication() {
    _refreshing = null;
    _loggingOut = false;
    return ++_sessionEpoch;
  }

  Future<void> writeSession(int epoch, Future<void> Function() operation) {
    final result = Completer<void>();
    _sessionWrites = _sessionWrites.then((_) async {
      try {
        checkSession(epoch);
        await operation();
        checkSession(epoch);
        result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  ApiClient({
    http.Client? client,
    TokenStore? tokenStorage,
    this.useRefreshCookie = kIsWeb,
  }) : _client = client ?? createHttpClient(),
       _tokenStorage = tokenStorage ?? SecureTokenStorage.instance;

  static ApiClient get instance {
    _instance ??= ApiClient();
    return _instance!;
  }

  /// Build full URL
  String _buildUrl(String endpoint) {
    final url = '${ApiConfig.baseUrl}$endpoint';
    return kIsWeb ? Uri.base.resolve(url).toString() : url;
  }

  /// Get headers with optional authentication
  Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (includeAuth) {
      final token = await _tokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  /// Handle HTTP response
  dynamic _handleResponse(http.Response response) {
    final statusCode = response.statusCode;

    // Try to parse response body
    dynamic body;
    try {
      body = response.body.isNotEmpty ? jsonDecode(response.body) : null;
    } catch (e) {
      body = {'message': response.body};
    }

    // Handle success
    if (statusCode >= 200 && statusCode < 300) {
      return body;
    }

    // Extract error message
    String message = 'Request failed';
    String? code;
    Map<String, dynamic>? details;

    if (body is Map<String, dynamic>) {
      if (body['error'] != null && body['error'] is Map) {
        final error = body['error'] as Map<String, dynamic>;
        message = error['message'] ?? message;
        code = error['code'];
        details = error['details'];
      } else {
        message = body['message'] ?? message;
        code = body['code'];
      }
    }

    // Throw appropriate exception
    switch (statusCode) {
      case 401:
        if (code == 'TOKEN_EXPIRED' ||
            code == 'AUTH_TOKEN_EXPIRED' ||
            code == 'AUTH_SESSION_INVALID') {
          throw TokenExpiredException(message: message);
        }
        throw UnauthorizedException(message: message);
      case 403:
        throw ForbiddenException(message: message);
      case 404:
        throw NotFoundException(message: message);
      case 400:
        throw ValidationException(message: message, details: details);
      case 500:
      case 502:
      case 503:
        throw ServerException(message: message);
      default:
        throw ApiException(
          message: message,
          code: code,
          statusCode: statusCode,
          details: details,
        );
    }
  }

  Never _handleError(Object error) {
    if (error is ApiException) throw error;
    if (error is http.ClientException || error is TimeoutException) {
      throw NetworkException(
        message: 'Không thể kết nối máy chủ. Vui lòng thử lại.',
      );
    }
    throw ApiException(message: 'Phản hồi máy chủ không hợp lệ.');
  }

  Future<void> _invalidateSession({int? expectedEpoch}) async {
    if (expectedEpoch != null && expectedEpoch != _sessionEpoch) return;
    final epoch = ++_sessionEpoch;
    _refreshing = null;
    try {
      await writeSession(epoch, _tokenStorage.clearAll);
    } on ApiException {
      return;
    }
    if (epoch == _sessionEpoch) sessionInvalidated.value++;
  }

  Future<void> clearSession({int? expectedEpoch}) =>
      _invalidateSession(expectedEpoch: expectedEpoch);

  /// Concurrent requests share one refresh operation; both tokens are rotated.
  Future<void> refreshToken({bool duringLogout = false}) async {
    if (_loggingOut && !duringLogout) {
      throw UnauthorizedException(message: 'Vui lòng đăng nhập lại.');
    }
    final pending = _refreshing;
    if (pending != null) return pending;
    final operation = _performRefresh(_sessionEpoch);
    _refreshing = operation;
    try {
      await operation;
    } finally {
      if (identical(_refreshing, operation)) _refreshing = null;
    }
  }

  void sessionStarted({int? expectedEpoch}) {
    if (expectedEpoch != null) {
      checkSession(expectedEpoch);
    } else {
      _sessionEpoch++;
    }
    _loggingOut = false;
  }

  /// Finish any token rotation before revoking the current device session.
  Future<void> logout({bool allDevices = false}) async {
    final epoch = _sessionEpoch;
    _loggingOut = true;
    try {
      final pending = _refreshing;
      if (pending != null) {
        try {
          await pending;
        } on ApiException {
          // The server may already have revoked the session.
        }
      }
      checkSession(epoch);
      await post(
        '${ApiConfig.authEndpoint}/${allDevices ? 'logout-all' : 'logout'}',
      );
    } finally {
      await _invalidateSession(expectedEpoch: epoch);
    }
  }

  Future<void> _performRefresh(int epoch) async {
    try {
      final refresh = await _tokenStorage.getRefreshToken();
      if (!useRefreshCookie && refresh == null) {
        throw UnauthorizedException(message: 'Vui lòng đăng nhập lại.');
      }
      final response = await _client
          .post(
            Uri.parse(_buildUrl('${ApiConfig.authEndpoint}/refresh')),
            headers: await _getHeaders(includeAuth: false),
            body: jsonEncode(refresh == null ? {} : {'refreshToken': refresh}),
          )
          .timeout(ApiConfig.receiveTimeout);
      final data = _handleResponse(response);
      final tokens = data?['data'];
      if (data?['success'] != true ||
          tokens?['accessToken'] is! String ||
          tokens?['refreshToken'] is! String) {
        throw UnauthorizedException(message: 'Vui lòng đăng nhập lại.');
      }
      checkSession(epoch);
      await writeSession(
        epoch,
        () => _tokenStorage.saveTokens(
          accessToken: tokens['accessToken'],
          refreshToken: tokens['refreshToken'],
        ),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _invalidateSession(expectedEpoch: epoch);
      }
      rethrow;
    } catch (error) {
      _handleError(error);
    }
  }

  Future<dynamic> _request(
    String method,
    String endpoint, {
    Map<String, String>? queryParameters,
    dynamic body,
    bool requiresAuth = true,
  }) async {
    final epoch = _sessionEpoch;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (requiresAuth) checkSession(epoch);
      final headers = await _getHeaders(includeAuth: requiresAuth);
      if (requiresAuth) checkSession(epoch);
      try {
        final uri = Uri.parse(_buildUrl(endpoint))
            .replace(queryParameters: queryParameters);
        final request = http.Request(method, uri)..headers.addAll(headers);
        if (body != null) request.body = jsonEncode(body);
        final response = await _client
            .send(request)
            .then(http.Response.fromStream)
            .timeout(ApiConfig.receiveTimeout);
        if (requiresAuth) checkSession(epoch);
        return _handleResponse(response);
      } on TokenExpiredException {
        checkSession(epoch);
        if (!requiresAuth || attempt > 0) {
          if (requiresAuth) await _invalidateSession(expectedEpoch: epoch);
          throw UnauthorizedException(message: 'Phiên đăng nhập đã hết hạn.');
        }
        // Another request may already have rotated the access token.
        final current = await _tokenStorage.getAccessToken();
        if (headers['Authorization'] ==
            (current == null ? null : 'Bearer $current')) {
          await refreshToken(
            duringLogout:
                _loggingOut &&
                (endpoint == '${ApiConfig.authEndpoint}/logout' ||
                    endpoint == '${ApiConfig.authEndpoint}/logout-all'),
          );
        }
      } on UnauthorizedException {
        if (requiresAuth) await _invalidateSession(expectedEpoch: epoch);
        rethrow;
      } catch (error) {
        _handleError(error);
      }
    }
    throw UnauthorizedException(message: 'Vui lòng đăng nhập lại.');
  }

  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool requiresAuth = true,
  }) => _request(
    'GET',
    endpoint,
    queryParameters: queryParameters,
    requiresAuth: requiresAuth,
  );
  Future<dynamic> post(
    String endpoint, {
    dynamic body,
    bool requiresAuth = true,
  }) => _request('POST', endpoint, body: body, requiresAuth: requiresAuth);
  Future<dynamic> put(
    String endpoint, {
    dynamic body,
    bool requiresAuth = true,
  }) => _request('PUT', endpoint, body: body, requiresAuth: requiresAuth);
  Future<dynamic> patch(
    String endpoint, {
    dynamic body,
    bool requiresAuth = true,
  }) => _request('PATCH', endpoint, body: body, requiresAuth: requiresAuth);
  Future<dynamic> delete(
    String endpoint, {
    dynamic body,
    bool requiresAuth = true,
  }) => _request('DELETE', endpoint, body: body, requiresAuth: requiresAuth);

  void dispose() {
    _client.close();
    sessionInvalidated.dispose();
  }
}
