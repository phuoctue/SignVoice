import 'package:sign_voice/core/app_state.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/features/home/home_screen.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/auth/auth_service.dart';

import 'auth_fixtures.dart';

http.Response success(dynamic data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);
http.Response expired() => http.Response(
  jsonEncode({
    'error': {'code': 'AUTH_TOKEN_EXPIRED', 'message': 'Expired'},
  }),
  401,
);

void main() {
  test('login reads the nested token pair and maps the API user id', () async {
    final store = MemoryTokenStore();
    final api = ApiClient(
      tokenStorage: store,
      useRefreshCookie: false,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/login');
        expect(request.headers['Authorization'], isNull);
        final user = testUser().toJson()..['id'] = '0123456789abcdef01234567';
        user.remove('_id');
        return success({
          'user': user,
          'tokens': {'accessToken': 'access', 'refreshToken': 'refresh'},
        });
      }),
    );
    final auth = AuthService(apiClient: api, tokenStorage: store);
    final user = await auth.login(
      email: 'user@example.com',
      password: 'Test1234',
    );
    expect(user.id, '0123456789abcdef01234567');
    expect(store.accessToken, 'access');
    expect(store.refreshToken, 'refresh');
    expect(store.role, 'USER');
    api.dispose();
  });

  test(
    'concurrent expired requests refresh once, save both tokens, and retry',
    () async {
      final store = MemoryTokenStore()
        ..accessToken = 'old-access'
        ..refreshToken = 'old-refresh';
      var refreshes = 0;
      final refreshStarted = Completer<void>();
      final allowRefresh = Completer<void>();
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            refreshes++;
            expect(jsonDecode(request.body)['refreshToken'], 'old-refresh');
            refreshStarted.complete();
            await allowRefresh.future;
            return success({
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
            });
          }
          if (request.headers['Authorization'] == 'Bearer old-access') {
            return expired();
          }
          expect(request.headers['Authorization'], 'Bearer new-access');
          return success({'ok': true});
        }),
      );
      final requests = Future.wait([
        api.get('/users/me'),
        api.get('/favorites'),
      ]);
      await refreshStarted.future;
      allowRefresh.complete();
      await requests;
      expect(refreshes, 1);
      expect(store.refreshToken, 'new-refresh');
      expect(store.writes, 1);
      api.dispose();
    },
  );

  test('retry stops after one refresh and invalidates the session', () async {
    final store = MemoryTokenStore()
      ..accessToken = 'old'
      ..refreshToken = 'refresh';
    var refreshes = 0;
    final api = ApiClient(
      tokenStorage: store,
      useRefreshCookie: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshes++;
          return success({'accessToken': 'new', 'refreshToken': 'new-refresh'});
        }
        return expired();
      }),
    );
    await expectLater(
      api.get('/users/me'),
      throwsA(isA<UnauthorizedException>()),
    );
    expect(refreshes, 1);
    expect(store.accessToken, isNull);
    expect(api.sessionInvalidated.value, 1);
    api.dispose();
  });

  test(
    'invalid refresh signs out the provider and clears credentials',
    () async {
      final store = MemoryTokenStore()
        ..accessToken = 'old'
        ..refreshToken = 'refresh';
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            return http.Response('{}', 401);
          }
          if (request.url.path.endsWith('/me')) {
            return success(testUser().toJson());
          }
          return expired();
        }),
      );
      final provider = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      await provider.initialize();
      expect(provider.isAuthenticated, true);
      await expectLater(
        api.get('/favorites'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(provider.isAuthenticated, false);
      expect(provider.user, isNull);
      expect(store.refreshToken, isNull);
      provider.dispose();
      api.dispose();
    },
  );

  test(
    'browser restoration refreshes using cookies without a body token',
    () async {
      final store = MemoryTokenStore()..role = 'USER';
      var refreshes = 0;
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: true,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            refreshes++;
            expect(jsonDecode(request.body), isEmpty);
            return success({
              'accessToken': 'access',
              'refreshToken': 'refresh',
            });
          }
          expect(request.headers['Authorization'], 'Bearer access');
          return success(testUser().toJson());
        }),
      );
      final service = AuthService(apiClient: api, tokenStorage: store);
      expect((await service.restoreSession())!.id, testUser().id);
      expect(refreshes, 1);
      api.dispose();
    },
  );

  test(
    'a signed-out browser does not restore a remaining server cookie',
    () async {
      var requests = 0;
      final store = MemoryTokenStore();
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: true,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 500);
        }),
      );
      final service = AuthService(apiClient: api, tokenStorage: store);
      expect(await service.restoreSession(), isNull);
      expect(requests, 0);
      api.dispose();
    },
  );

  test('logout waits for rotation and revokes the resulting session', () async {
    final store = MemoryTokenStore()
      ..accessToken = 'old'
      ..refreshToken = 'refresh';
    final refreshStarted = Completer<void>();
    final allowRefresh = Completer<void>();
    var loggedOut = false;
    final api = ApiClient(
      tokenStorage: store,
      useRefreshCookie: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshStarted.complete();
          await allowRefresh.future;
          return success({
            'accessToken': 'rotated',
            'refreshToken': 'rotated-refresh',
          });
        }
        expect(request.url.path, '/api/v1/auth/logout');
        expect(request.headers['Authorization'], 'Bearer rotated');
        loggedOut = true;
        return success({});
      }),
    );
    final refreshing = api.refreshToken();
    await refreshStarted.future;
    final logout = api.logout();
    await expectLater(
      api.refreshToken(),
      throwsA(isA<UnauthorizedException>()),
    );
    allowRefresh.complete();
    await refreshing;
    await logout;
    expect(loggedOut, true);
    expect(store.accessToken, isNull);
    expect(store.refreshToken, isNull);
    api.dispose();
  });

  test(
    'logout refreshes an expired access token before revoking the session',
    () async {
      final store = MemoryTokenStore()
        ..accessToken = 'old'
        ..refreshToken = 'refresh';
      var refreshes = 0;
      var logouts = 0;
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            refreshes++;
            return success({
              'accessToken': 'new',
              'refreshToken': 'new-refresh',
            });
          }
          logouts++;
          return request.headers['Authorization'] == 'Bearer old'
              ? expired()
              : success({});
        }),
      );
      await api.logout();
      expect(refreshes, 1);
      expect(logouts, 2);
      expect(store.accessToken, isNull);
      expect(store.refreshToken, isNull);
      api.dispose();
    },
  );

  test('network errors during refresh keep tokens for retry', () async {
    final store = MemoryTokenStore()
      ..accessToken = 'access'
      ..refreshToken = 'refresh';
    final api = ApiClient(
      tokenStorage: store,
      useRefreshCookie: false,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(api.refreshToken(), throwsA(isA<NetworkException>()));
    expect(store.refreshToken, 'refresh');
    api.dispose();
  });

  test(
    'logout clears local credentials even when the server is unreachable',
    () async {
      final store = MemoryTokenStore()
        ..accessToken = 'access'
        ..refreshToken = 'refresh';
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final provider = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      await provider.logout();
      expect(provider.state, AuthState.unauthenticated);
      expect(store.accessToken, isNull);
      expect(store.refreshToken, isNull);
      provider.dispose();
      api.dispose();
    },
  );

  testWidgets('unauthenticated direct routes show login', (tester) async {
    final auth = AuthProvider(authService: FakeAuthService());
    await auth.initialize();
    await tester.pumpWidget(
      SignVoiceApp(initialScreen: 'S08', auth: auth, state: AppState()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });

  testWidgets('USER cannot open admin or staff routes', (tester) async {
    final auth = await authenticatedProvider();
    for (final route in ['admin', 'staff']) {
      await tester.pumpWidget(
        SignVoiceApp(
          key: ValueKey(route),
          initialScreen: route,
          auth: auth,
          state: AppState(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Bạn không có quyền truy cập trang này.'),
        findsOneWidget,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });

  testWidgets(
    'successful login opens home and logout removes protected content',
    (tester) async {
      final auth = AuthProvider(authService: FakeAuthService());
      await auth.initialize();
      await tester.pumpWidget(
        SignVoiceApp(initialScreen: 'S05', auth: auth, state: AppState()),
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'user@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Test1234');
      final login = find.widgetWithText(FilledButton, 'Đăng nhập');
      await tester.ensureVisible(login);
      await tester.tap(login);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
    },
  );

  testWidgets('failed credentials keep the login form visible', (tester) async {
    final service = FakeAuthService()..failLogin = true;
    final auth = AuthProvider(authService: service);
    await auth.initialize();
    await tester.pumpWidget(
      SignVoiceApp(initialScreen: 'S05', auth: auth, state: AppState()),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Test1234');
    final login = find.widgetWithText(FilledButton, 'Đăng nhập');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Đăng nhập'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
  });
}
