import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/auth/auth_service.dart';
import 'package:sign_voice/services/user/user_data_service.dart';

import 'auth_fixtures.dart';

http.Response ok(dynamic data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
http.Response failure(int status, String code, String message) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': message},
  }),
  status,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('service flow keeps the same owner and reads retained data after conversion and login', () async {
    final owned = <String, dynamic>{
      'settings': {'theme': 'DARK', 'fontSize': 20},
      'favorites': ['entry-1'],
      'conversations': <dynamic>[],
      'searchHistory': ['xin chào'],
      'progress': [
        {'topic': 'topic-1', 'remembered': 2},
      ],
      'personalWords': ['từ riêng'],
      'quizEvents': ['event-1'],
      'collections': [
        {
          'id': 'collection-1',
          'notes': ['ghi chú'],
        },
      ],
      'reports': ['report-1'],
      'notifications': ['notification-1'],
      'guestTrial': {'expiresAt': '2026-11-14T00:10:00Z'},
    };
    final store = MemoryTokenStore();
    final writes = <String>[];
    final api = ApiClient(
      tokenStorage: store,
      useRefreshCookie: false,
      client: MockClient((r) async {
        final path = r.url.path;
        if (r.method != 'GET') writes.add('${r.method} $path');
        if (path.endsWith('/guest') || path.endsWith('/login')) {
          return ok({
            'user': testUser(guest: path.endsWith('/guest')).toJson(),
            'tokens': {'accessToken': 'access', 'refreshToken': 'refresh'},
          });
        }
        if (path.endsWith('/convert-guest')) {
          expect(jsonDecode(r.body), {
            'email': 'guest@example.com',
            'password': 'Pass12345',
            'displayName': 'Guest',
            'requireLogin': true,
          });
          return ok({'user': testUser().toJson(), 'loginRequired': true});
        }
        if (path.endsWith('/conversations') && r.method == 'POST') {
          final conversation = {
            '_id': 'conversation-1',
            ...jsonDecode(r.body) as Map,
          };
          (owned['conversations'] as List).add(conversation);
          return ok(conversation);
        }
        if (path.endsWith('/users/data/export')) {
          return ok({'userId': testUser().id, ...owned});
        }
        throw StateError('Unexpected request ${r.method} $path');
      }),
    );
    final auth = AuthService(apiClient: api, tokenStorage: store);
    final data = UserDataService(apiClient: api);
    final guest = await auth.loginAsGuest();
    await data.saveConversation('Nội dung đã lưu', 'TEXT');
    final before = await data.exportData();
    final converted = await auth.convertGuest(
      email: 'guest@example.com',
      password: 'Pass12345',
      displayName: 'Guest',
    );
    expect(converted.id, guest.id);
    expect(store.accessToken, isNull);
    final permanent = await auth.login(
      email: 'guest@example.com',
      password: 'Pass12345',
    );
    expect(permanent.id, guest.id);
    expect(await data.exportData(), before);
    expect(writes, [
      'POST /api/v1/auth/guest',
      'POST /api/v1/conversations',
      'POST /api/v1/auth/convert-guest',
      'POST /api/v1/auth/login',
    ]);
    api.dispose();
  });

  test('cutoff is optional and survives a profile copy', () {
    final json = testUser(guest: true).toJson();
    expect(
      UserModel.fromJson(json).toJson()['legacyGuestSessionCutoffAt'],
      isNull,
    );
    json['legacyGuestSessionCutoffAt'] = '2026-11-20T12:30:00.000Z';
    expect(
      UserModel.fromJson(json)
          .copyWith(displayName: 'Guest')
          .toJson()['legacyGuestSessionCutoffAt'],
      '2026-11-20T12:30:00.000Z',
    );
  });

  for (final code in ['AUTH_SESSION_INVALID']) {
    test('conversion never resubmits after $code', () async {
      final paths = <String>[];
      final store = MemoryTokenStore()
        ..accessToken = 'guest'
        ..refreshToken = 'refresh';
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path.endsWith('/refresh')) {
            return ok({'accessToken': 'new', 'refreshToken': 'new'});
          }
          return failure(401, code, 'Session changed');
        }),
      );
      final service = AuthService(apiClient: api, tokenStorage: store);
      await expectLater(
        service.convertGuest(
          email: 'guest@example.com',
          password: 'Pass12345',
          displayName: 'Guest',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(paths, ['/api/v1/auth/convert-guest']);
      expect(store.accessToken, isNull);
      api.dispose();
    });
  }

  for (final cause in [
    'refresh denial',
    'natural expiry',
    'deadline',
    'unauthorized',
  ]) {
    test('$cause clears local guest auth without destructive logout', () async {
      final paths = <String>[];
      var expired = false;
      final store = MemoryTokenStore()
        ..accessToken = 'guest'
        ..refreshToken = 'refresh';
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((r) async {
          paths.add(r.url.path);
          if (!expired && r.url.path.endsWith('/me')) {
            return ok(testUser(guest: true).toJson());
          }
          if (r.url.path.contains('/guest-trial/')) {
            return ok({
              'state': 'expired',
              'serverNow': '2026-11-14T00:00:00Z',
            });
          }
          if (r.url.path.endsWith('/refresh')) {
            return cause == 'natural expiry'
                ? ok({'accessToken': 'new', 'refreshToken': 'new'})
                : failure(401, 'AUTH_SESSION_INVALID', 'Expired');
          }
          return failure(
            401,
            cause == 'deadline'
                ? 'AUTH_SESSION_INVALID'
                : cause == 'unauthorized'
                ? 'AUTH_TOKEN_INVALID'
                : 'AUTH_TOKEN_EXPIRED',
            'Expired',
          );
        }),
      );
      final provider = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      await provider.initialize();
      expired = true;
      await provider.refreshUser();
      expect(provider.state, AuthState.unauthenticated);
      expect(store.accessToken, isNull);
      expect(paths.where((p) => p.contains('logout')), isEmpty);
      provider.dispose();
      api.dispose();
    });
  }

  test('guest draft survives re-login to the same id and stays hidden from another account', () {
    final state = AppState()..bindAccount('guest-id', asGuest: true);
    state.sentence.add('Xin chào');
    state.transcript = 'Bản nháp';
    state.unbindAccount();
    state.bindAccount('other-id', asGuest: false);
    expect(state.sentence, isEmpty);
    expect(state.transcript, isEmpty);
    state.unbindAccount();
    state.bindAccount('guest-id', asGuest: false);
    expect(state.sentence, ['Xin chào']);
    expect(state.transcript, 'Bản nháp');
    state.dispose();
  });
}
