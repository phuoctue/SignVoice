import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/auth/auth_service.dart';

import 'auth_fixtures.dart';
import 'guest_conversion_test.dart' show ok, failure;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final cookie in [false, true]) {
    for (final guest in [false, true]) {
      test(
        '${cookie ? 'web' : 'native'} reopen restores ${guest ? 'guest' : 'permanent'} when server accepts it',
        () async {
          final store = MemoryTokenStore()
            ..role = 'USER'
            ..refreshToken = 'refresh';
          if (!cookie) {
            store.accessToken = 'access';
          }
          final paths = <String>[];
          final api = ApiClient(
            tokenStorage: store,
            useRefreshCookie: cookie,
            client: MockClient((r) async {
              paths.add(r.url.path);
              if (r.url.path.endsWith('/refresh')) {
                return ok({
                  'accessToken': 'restored',
                  'refreshToken': 'rotated',
                });
              }
              if (r.url.path.endsWith('/me')) {
                return ok(testUser(guest: guest).toJson());
              }
              return ok({
                'state': 'expired',
                'serverNow': '2026-11-14T00:00:00Z',
              });
            }),
          );
          final provider = AuthProvider(
            authService: AuthService(apiClient: api, tokenStorage: store),
          );
          await provider.initialize();
          expect(provider.isAuthenticated, true);
          expect(provider.user?.isGuest, guest);
          expect(provider.user?.id, testUser().id);
          await provider.refreshUser();
          expect(
            paths.where(
              (p) => p.endsWith('/auth/guest') || p.contains('logout'),
            ),
            isEmpty,
          );
          provider.dispose();
          api.dispose();
        },
      );
    }
    for (final code in [
      'AUTH_SESSION_INVALID',
      'AUTH_USER_NOT_FOUND',
      'AUTH_TOKEN_EXPIRED',
    ]) {
      test(
        '${cookie ? 'web' : 'native'} reopen rejection $code clears only local auth',
        () async {
          final store = MemoryTokenStore()
            ..role = 'USER'
            ..refreshToken = 'refresh';
          if (!cookie) {
            store.accessToken = 'expired';
          }
          final paths = <String>[];
          final api = ApiClient(
            tokenStorage: store,
            useRefreshCookie: cookie,
            client: MockClient((r) async {
              paths.add(r.url.path);
              return failure(401, code, 'Session expired');
            }),
          );
          final provider = AuthProvider(
            authService: AuthService(apiClient: api, tokenStorage: store),
          );
          await provider.initialize();
          expect(provider.state, AuthState.unauthenticated);
          expect(store.accessToken, isNull);
          expect(store.refreshToken, isNull);
          expect(
            paths.where(
              (p) => p.contains('logout') || p.endsWith('/auth/guest'),
            ),
            isEmpty,
          );
          provider.dispose();
          api.dispose();
        },
      );
    }
  }
  test(
    'missing refresh cookie is a non-destructive server rejection',
    () async {
      final store = MemoryTokenStore()..role = 'USER';
      final paths = <String>[];
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: true,
        client: MockClient((r) async {
          paths.add(r.url.path);
          return failure(400, 'AUTH_TOKEN_MISSING', 'Refresh token required');
        }),
      );
      final provider = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      await provider.initialize();
      expect(provider.state, AuthState.unauthenticated);
      expect(store.role, isNull);
      expect(paths, ['/api/v1/auth/refresh']);
      provider.dispose();
      api.dispose();
    },
  );
}
