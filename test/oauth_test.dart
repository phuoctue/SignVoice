import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/features/auth/oauth_complete_screen.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/auth/auth_service.dart';

import 'auth_fixtures.dart';

void main() {
  for (final register in [false, true]) {
    testWidgets(
      'social providers are available on ${register ? 'registration' : 'login'}',
      (tester) async {
        final store = MemoryTokenStore();
        var providerRequests = 0;
        final api = ApiClient(
          tokenStorage: store,
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/auth/oauth/providers');
            providerRequests++;
            return http.Response(
              '{"success":true,"data":{"google":true,"facebook":false}}',
              200,
            );
          }),
        );
        final auth = AuthProvider(
          authService: AuthService(apiClient: api, tokenStorage: store),
        );
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: auth,
            child: MaterialApp(home: AuthScreen(register: register)),
          ),
        );
        await tester.pumpAndSettle();
        expect(providerRequests, 1);
        expect(find.text('Tiếp tục với Google'), findsOneWidget);
        expect(find.text('Tiếp tục với Facebook'), findsOneWidget);
        expect(
          find.text(
            'Một số nhà cung cấp chưa được cấu hình. Đăng nhập email và dùng thử vẫn hoạt động.',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        auth.dispose();
        api.dispose();
      },
    );
  }
  test(
    'wrong current password preserves real client session and allows retry',
    () async {
      final store = MemoryTokenStore();
      var changes = 0;
      final paths = <String>[];
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/login')) {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'user': testUser().toJson(),
                  'tokens': {
                    'accessToken': 'valid-access',
                    'refreshToken': 'valid-refresh',
                  },
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(request.url.path, '/api/v1/auth/change-password');
          expect(request.headers['Authorization'], 'Bearer valid-access');
          changes++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['currentPassword'] == 'wrong') {
            return http.Response(
              jsonEncode({
                'success': false,
                'error': {
                  'code': 'VALIDATION_ERROR',
                  'message': 'Mật khẩu hiện tại không đúng.',
                },
              }),
              400,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(body['currentPassword'], 'CurrentPassword123');
          return http.Response(
            '{"success":true,"data":{"message":"Password changed"}}',
            200,
          );
        }),
      );
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      expect(
        await auth.login(
          email: 'user@example.com',
          password: 'CurrentPassword123',
        ),
        isTrue,
      );
      expect(
        await auth.changePassword(
          currentPassword: 'wrong',
          newPassword: 'NewPassword123',
        ),
        isFalse,
      );
      expect(auth.isAuthenticated, isTrue);
      expect(auth.user?.id, testUser().id);
      expect(auth.errorMessage, 'Mật khẩu hiện tại không đúng.');
      expect(store.accessToken, 'valid-access');
      expect(store.refreshToken, 'valid-refresh');
      expect(store.role, 'USER');
      expect(api.sessionInvalidated.value, 0);
      expect(changes, 1);
      expect(paths, isNot(contains('/api/v1/auth/refresh')));
      expect(
        await auth.changePassword(
          currentPassword: 'CurrentPassword123',
          newPassword: 'NewPassword123',
        ),
        isTrue,
      );
      expect(changes, 2);
      expect(auth.isAuthenticated, isFalse);
      expect(store.accessToken, isNull);
      expect(store.refreshToken, isNull);
      expect(api.sessionInvalidated.value, 1);
      auth.dispose();
      api.dispose();
    },
  );
  test(
    'OAuth completion bootstraps user and metadata without prior local login',
    () async {
      final store = MemoryTokenStore();
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: true,
        client: MockClient((req) async {
          expect(req.method, 'POST');
          expect(req.url.path, '/api/v1/auth/oauth/complete');
          expect(req.headers['Authorization'], isNull);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'user': testUser().toJson(),
                'tokens': {
                  'accessToken': 'oauth-access',
                  'refreshToken': 'oauth-refresh',
                },
              },
            }),
            200,
          );
        }),
      );
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      expect(await auth.completeOAuth(), isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(store.role, 'USER');
      expect(store.accessToken, 'oauth-access');
      auth.dispose();
      api.dispose();
    },
  );
  test(
    'disabled providers are explicit and never synthesize a login',
    () async {
      final store = MemoryTokenStore();
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient((req) async {
          expect(req.url.path, '/api/v1/auth/oauth/providers');
          return http.Response(
            '{"success":true,"data":{"google":false,"facebook":false}}',
            200,
          );
        }),
      );
      final service = AuthService(apiClient: api, tokenStorage: store);
      expect(await service.oauthProviders(), {
        'google': false,
        'facebook': false,
      });
      expect(store.accessToken, isNull);
      api.dispose();
    },
  );
  testWidgets(
    'callback cancellation shows safe explanation without session completion',
    (tester) async {
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((_) async => throw StateError('Must not call API')),
      );
      final auth = AuthProvider(
        authService: AuthService(
          apiClient: api,
          tokenStorage: MemoryTokenStore(),
        ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(
            home: OAuthCompleteScreen(error: 'OAUTH_CANCELLED'),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Bạn đã hủy đăng nhập'), findsOneWidget);
      expect(find.text('Quay lại đăng nhập'), findsOneWidget);
      expect(auth.isAuthenticated, isFalse);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    },
  );
  testWidgets(
    'callback failed completion stays unauthenticated with retry navigation',
    (tester) async {
      final store = MemoryTokenStore();
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"code":"OAUTH_SESSION_MISSING","message":"Phiên không tồn tại"}}',
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: OAuthCompleteScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Phiên không tồn tại'), findsOneWidget);
      expect(auth.isAuthenticated, isFalse);
      expect(store.accessToken, isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    },
  );
}
