import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/auth/auth_service.dart';

import 'auth_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('signvoice/google');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  Map<String, dynamic> user({bool linked = true}) => {
    'id': 'existing-staff',
    'email': 'staff@example.com',
    'displayName': 'Staff',
    'role': 'STAFF',
    'accountType': 'LOCAL',
    'isGuest': false,
    'status': 'ACTIVE',
    'googleLinked': linked,
    'createdAt': '2026-01-01T00:00:00Z',
  };
  http.Response ok(Object data) =>
      http.Response(jsonEncode({'success': true, 'data': data}), 200);

  test('Google SDK uses server nonce and Web audience, then stores only application tokens', () async {
    final store = MemoryTokenStore();
    final paths = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'signIn');
      expect(call.arguments, {
        'clientId': 'web-client.apps.googleusercontent.com',
        'nonce': 'server-nonce',
      });
      return 'google-signed-proof';
    });
    final api = ApiClient(
      tokenStorage: store,
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/challenge')) {
          return ok({
            'challenge': 'one-use',
            'nonce': 'server-nonce',
            'clientId': 'web-client.apps.googleusercontent.com',
          });
        }
        expect(jsonDecode(request.body), {
          'challenge': 'one-use',
          'idToken': 'google-signed-proof',
        });
        return ok({
          'user': user(),
          'tokens': {
            'accessToken': 'app-access',
            'refreshToken': 'app-refresh',
          },
        });
      }),
    );
    addTearDown(api.dispose);
    final result = await AuthService(
      apiClient: api,
      tokenStorage: store,
    ).signInGoogle();
    expect(result.id, 'existing-staff');
    expect(result.isStaff, true);
    expect(result.googleLinked, true);
    expect(store.accessToken, 'app-access');
    expect(store.refreshToken, 'app-refresh');
    expect(paths.length, 2);
  });
  test('cancellation never creates an application session', () async {
    final store = MemoryTokenStore();
    var calls = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'GOOGLE_CANCELLED'),
    );
    final api = ApiClient(
      tokenStorage: store,
      client: MockClient((_) async {
        calls++;
        return ok({
          'challenge': 'one-use',
          'nonce': 'nonce',
          'clientId': 'web-client.apps.googleusercontent.com',
        });
      }),
    );
    addTearDown(api.dispose);
    await expectLater(
      AuthService(apiClient: api, tokenStorage: store).signInGoogle(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'GOOGLE_CANCELLED'),
      ),
    );
    expect(calls, 1);
    expect(store.accessToken, isNull);
  });
  test(
    'late Google response after session change cannot complete login',
    () async {
      final selected = Completer<void>(), proof = Completer<String>();
      final store = MemoryTokenStore();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) {
        selected.complete();
        return proof.future;
      });
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient((_) async {
          calls++;
          return ok({
            'challenge': 'one-use',
            'nonce': 'nonce',
            'clientId': 'web-client.apps.googleusercontent.com',
          });
        }),
      );
      addTearDown(api.dispose);
      final pending = AuthService(
        apiClient: api,
        tokenStorage: store,
      ).signInGoogle();
      final rejected = expectLater(pending, throwsA(isA<ApiException>()));
      await selected.future;
      api.beginAuthentication();
      proof.complete('late-proof');
      await rejected;
      expect(calls, 1);
      expect(store.accessToken, isNull);
    },
  );
  test('linking sends authenticated proof and preserves existing application tokens', () async {
    final store = MemoryTokenStore()
      ..accessToken = 'original-access'
      ..refreshToken = 'original-refresh';
    messenger.setMockMethodCallHandler(channel, (_) async => 'google-proof');
    final api = ApiClient(
      tokenStorage: store,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/challenge')) {
          return ok({
            'challenge': 'one-use',
            'nonce': 'nonce',
            'clientId': 'web-client.apps.googleusercontent.com',
          });
        }
        expect(request.url.path, endsWith('/native/link'));
        expect(request.headers['Authorization'], 'Bearer original-access');
        return ok({'user': user()});
      }),
    );
    addTearDown(api.dispose);
    final result = await AuthService(
      apiClient: api,
      tokenStorage: store,
    ).linkGoogle();
    expect(result.id, 'existing-staff');
    expect(result.googleLinked, true);
    expect(store.accessToken, 'original-access');
    expect(store.refreshToken, 'original-refresh');
  });
}
