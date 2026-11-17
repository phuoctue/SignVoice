import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/auth/auth_service.dart';
import 'package:sign_voice/services/auth/guest_grant_operation.dart';
import 'package:sign_voice/services/auth/guest_trial_access.dart';
import 'package:sign_voice/providers/auth_provider.dart';

import 'auth_fixtures.dart';

http.Response envelope(dynamic data, [int status = 200]) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> trialStatus(String state, {bool eligible = false}) => {
  'state': state == 'trial_active' ? 'active' : 'expired',
  'serverNow': '2026-11-15T00:00:00.123Z',
  'startedAt': state == 'legacy_unknown' ? null : '2026-11-14T23:55:00.123Z',
  'expiresAt': state == 'legacy_unknown' ? null : '2026-11-15T00:05:00.123Z',
  'dataRetainedUntil': state == 'legacy_unknown'
      ? null
      : '2026-11-21T23:55:00.123Z',
  'nextTrialAvailableAt': '2026-11-15T23:55:00.123Z',
  'dataState': state,
  'dataVersion': 7,
  'allowedActions': [
    'status',
    'auth_me',
    'refresh',
    'logout',
    'discard',
    if (state != 'expired') 'convert',
    if (eligible && state != 'legacy_unknown') 'new_trial',
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('a separately confirmed standalone operation can leave an unrecoverable replacement without adopting its authority', () async {
    await GuestGrantOperation.observe('2026-11-16T04:05:06.789Z');
    final replacement = await GuestGrantOperation.loadOrCreate(
      dataVersion: 7,
      ownerId: 'old-guest',
    );
    await expectLater(
      GuestGrantOperation.loadOrCreate(),
      throwsA(isA<StateError>()),
    );
    await GuestGrantOperation.beginSeparateOperation();
    final fresh = await GuestGrantOperation.loadOrCreate();
    expect(fresh['requestKey'], isNot(replacement['requestKey']));
    expect(fresh['expectedLastGrantAt'], '2026-11-15T04:05:06.789Z');
    expect(fresh.containsKey('confirmDiscard'), false);
    expect(fresh.containsKey('ownerId'), false);
  });
  test(
    'an older response cannot clear a newer pending grant in another tab',
    () async {
      final prior = await GuestGrantOperation.loadOrCreate();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'signvoice_guest_grant_pending',
        jsonEncode({'requestKey': 'newer', 'expectedLastGrantAt': null}),
      );
      await GuestGrantOperation.finish(prior['requestKey'] as String);
      expect(
        jsonDecode(
          prefs.getString('signvoice_guest_grant_pending')!,
        )['requestKey'],
        'newer',
      );
    },
  );
  for (final state in [
    'trial_active',
    'retained',
    'expired',
    'legacy_unknown',
  ]) {
    test(
      '$state restore and status never grant/logout/discard; expired conversion is blocked',
      () async {
        final paths = <String>[];
        final store = MemoryTokenStore()..accessToken = 'guest';
        final api = ApiClient(
          tokenStorage: store,
          client: MockClient((r) async {
            paths.add('${r.method} ${r.url.path}');
            return envelope(
              r.url.path.endsWith('/me')
                  ? testUser(guest: true).toJson()
                  : trialStatus(state),
            );
          }),
        );
        final auth = AuthProvider(
          authService: AuthService(apiClient: api, tokenStorage: store),
        );
        await auth.initialize();
        await auth.refreshUser();
        await auth.loadGuestTrial();
        if (state == 'expired') {
          expect(
            await auth.convertGuest(
              email: 'x@example.test',
              password: 'Pass2026!',
              displayName: 'User',
            ),
            false,
          );
        }
        expect(paths.every((p) => p.startsWith('GET ')), true);
        auth.dispose();
        api.dispose();
      },
    );
  }
  for (final outcome in [
    'confirmed',
    'lost',
    'unauthorized',
    'accepted',
    'malformed',
  ]) {
    test(
      'discard $outcome never claims an unconfirmed deletion or issues logout',
      () async {
        final requests = <String>[];
        final store = MemoryTokenStore()..accessToken = 'guest';
        final api = ApiClient(
          tokenStorage: store,
          client: MockClient((r) async {
            requests.add('${r.method} ${r.url.path}');
            if (r.url.path.endsWith('/me')) {
              return envelope(testUser(guest: true).toJson());
            }
            if (r.url.path.endsWith('/status')) {
              return envelope(trialStatus('expired'));
            }
            if (outcome == 'lost') throw http.ClientException('lost');
            if (outcome == 'unauthorized') {
              return http.Response(
                '{"error":{"code":"AUTH_SESSION_INVALID"}}',
                401,
              );
            }
            return envelope({
              'discarded': outcome != 'malformed',
            }, outcome == 'accepted' ? 202 : 200);
          }),
        );
        final provider = AuthProvider(
          authService: AuthService(apiClient: api, tokenStorage: store),
        );
        await provider.initialize();
        expect(await provider.discardGuest(), outcome == 'confirmed');
        expect(
          provider.guestOperationMessage?.contains('Đã xóa'),
          outcome == 'confirmed',
        );
        expect(
          requests.where(
            (r) =>
                r.contains('logout') ||
                r.contains('/auth/guest') ||
                r.contains('/start'),
          ),
          isEmpty,
        );
        expect(requests.where((r) => r.contains('/discard')).length, 1);
        provider.dispose();
        api.dispose();
      },
    );
  }
  test('CAS inverse preserves integer milliseconds and null, round trips the pinned 24h constant', () {
    expect(expectedLastGrantAt(null), isNull);
    expect(
      expectedLastGrantAt('2026-11-16T04:05:06.789Z'),
      '2026-11-15T04:05:06.789Z',
    );
    final prior = DateTime.parse(
      expectedLastGrantAt('2026-11-16T04:05:06.789Z')!,
    );
    expect(
      prior.millisecondsSinceEpoch + 86400000,
      DateTime.parse('2026-11-16T04:05:06.789Z').millisecondsSinceEpoch,
    );
  });
  test(
    'unknown or legacy status never fabricates ten minutes or new actions',
    () {
      final value = GuestTrialAccess.fromJson({
        'state': 'active',
        'serverNow': '2026-11-15T00:00:00Z',
      });
      expect(value.remaining, Duration.zero);
      expect(value.allows('convert'), false);
      expect(value.allows('new_trial'), false);
      final legacy = GuestTrialAccess.fromJson(trialStatus('legacy_unknown'));
      expect(legacy.remaining, Duration.zero);
      expect(legacy.allows('convert'), true);
      expect(legacy.allows('new_trial'), false);
    },
  );
  test('grant persists its random key and CAS before transport and replays after restart', () async {
    final bodies = <Map<String, dynamic>>[];
    final store = MemoryTokenStore();
    final api = ApiClient(
      tokenStorage: store,
      client: MockClient((r) async {
        expect(r.url.path.endsWith('/auth/guest'), true);
        final body = Map<String, dynamic>.from(jsonDecode(r.body));
        final prefs = await SharedPreferences.getInstance();
        expect(
          jsonDecode(
            prefs.getString('signvoice_guest_grant_pending')!,
          )['requestKey'],
          body['requestKey'],
        );
        bodies.add(body);
        throw http.ClientException('lost response');
      }),
    );
    var service = AuthService(apiClient: api, tokenStorage: store);
    await expectLater(service.loginAsGuest(), throwsA(isA<ApiException>()));
    service = AuthService(apiClient: api, tokenStorage: store);
    await expectLater(service.loginAsGuest(), throwsA(isA<ApiException>()));
    expect(bodies[1], bodies[0]);
    expect(bodies[0]['requestKey'], matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(bodies[0]['expectedLastGrantAt'], isNull);
    expect(bodies[0].containsKey('newGuest'), false);
    api.dispose();
  });
  test('409 ends only that operation; separate next consent uses server CAS and a new key', () async {
    final bodies = <Map<String, dynamic>>[];
    final store = MemoryTokenStore();
    final api = ApiClient(
      tokenStorage: store,
      client: MockClient((r) async {
        bodies.add(Map<String, dynamic>.from(jsonDecode(r.body)));
        return http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'GUEST_GRANT_STALE', 'message': 'conflict'},
            'data': {
              'serverNow': '2026-11-16T00:00:00Z',
              'nextTrialAvailableAt': '2026-11-15T04:05:06.789Z',
            },
          }),
          409,
        );
      }),
    );
    final service = AuthService(apiClient: api, tokenStorage: store);
    await expectLater(service.loginAsGuest(), throwsA(isA<ApiException>()));
    expect(bodies.length, 1);
    await expectLater(service.loginAsGuest(), throwsA(isA<ApiException>()));
    expect(bodies[1]['expectedLastGrantAt'], '2026-11-14T04:05:06.789Z');
    expect(bodies[1]['requestKey'], isNot(bodies[0]['requestKey']));
    api.dispose();
  });
  test(
    'intervening grant cannot rewrite a pending replay expectation',
    () async {
      final bodies = <dynamic>[];
      var lost = true;
      final store = MemoryTokenStore();
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return envelope(trialStatus('retained', eligible: true));
          }
          bodies.add(jsonDecode(r.body));
          if (lost) throw http.ClientException('lost');
          return http.Response(
            jsonEncode({
              'error': {'code': 'GUEST_GRANT_STALE', 'message': 'stale'},
              'data': {
                'serverNow': '2026-11-19T00:00:00Z',
                'nextTrialAvailableAt': '2026-11-19T04:00:00Z',
              },
            }),
            409,
          );
        }),
      );
      final service = AuthService(apiClient: api, tokenStorage: store);
      await expectLater(service.loginAsGuest(), throwsA(isA<ApiException>()));
      await service.guestTrial();
      lost = false;
      await expectLater(service.loginAsGuest(), throwsA(isA<ApiException>()));
      expect(bodies[1], bodies[0]);
      api.dispose();
    },
  );
  test('status uses GET and never creates an allowance', () async {
    final paths = <String>[];
    final api = ApiClient(
      tokenStorage: MemoryTokenStore(),
      client: MockClient((r) async {
        paths.add('${r.method} ${r.url.path}');
        return envelope(trialStatus('retained'));
      }),
    );
    await AuthService(apiClient: api).guestTrial();
    expect(paths, ['GET /api/v1/guest-trial/status']);
    api.dispose();
  });
}
