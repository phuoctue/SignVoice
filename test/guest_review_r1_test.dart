import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/auth/auth_service.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/widgets/guest_data_panel.dart'
    show confirmGuestLogout;
import 'package:provider/provider.dart';
import 'package:sign_voice/services/user/user_data_service.dart';

import 'auth_fixtures.dart';
import 'guest_conversion_test.dart' show failure;
import 'guest_v1_service_test.dart' show envelope, trialStatus;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'legacy RS1 separates a known session cutoff from an unknown cleanup deadline',
    (tester) async {
      final store = MemoryTokenStore()..accessToken = 'guest';
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient(
          (r) async => envelope(
            r.url.path.endsWith('/me')
                ? testUser(guest: true)
                      .copyWith(
                        legacyGuestSessionCutoffAt: DateTime.parse(
                          '2026-11-17T12:00:00Z',
                        ),
                      )
                      .toJson()
                : trialStatus('legacy_unknown'),
          ),
        ),
      );
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      await auth.initialize();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => confirmGuestLogout(context),
                  child: const Text('Thoát'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Thoát'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('không thể hẹn ngày dọn dữ liệu'),
        findsOneWidget,
      );
      expect(find.textContaining('Phiên khách hết hạn:'), findsOneWidget);
      expect(find.textContaining('24 giờ'), findsNothing);
      await tester.tap(find.text('Ở lại'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    },
  );
  testWidgets(
    'unverified guest registration waits for status then offers conversion',
    (tester) async {
      var offline = true;
      final writes = <String>[];
      final store = MemoryTokenStore()..accessToken = 'guest';
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient((r) async {
          if (r.method != 'GET') writes.add(r.url.path);
          if (r.url.path.endsWith('/me')) {
            return envelope(testUser(guest: true).toJson());
          }
          if (r.url.path.endsWith('/providers')) {
            return envelope({'google': false, 'facebook': false});
          }
          if (offline) throw http.ClientException('offline');
          return envelope(trialStatus('retained'));
        }),
      );
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      await auth.initialize();
      final state = AppState();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: AppScope(
            state: state,
            child: const MaterialApp(home: AuthScreen(register: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (var i = 0; i < 4; i++) {
        await tester.enterText(
          fields.at(i),
          ['Guest', 'g@example.test', 'Password2026!', 'Password2026!'][i],
        );
      }
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      offline = false;
      await auth.loadGuestTrial();
      await tester.pumpAndSettle();
      expect(find.text('Chuyển thành tài khoản'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
      state.dispose();
    },
  );
  test('private GUEST_TRIAL_EXPIRED 403 refreshes metadata without invalidating auth', () async {
    var denied = false;
    final store = MemoryTokenStore()
      ..accessToken = 'guest'
      ..refreshToken = 'refresh';
    final api = ApiClient(
      tokenStorage: store,
      client: MockClient((r) async {
        if (r.url.path.endsWith('/me')) {
          return envelope(testUser(guest: true).toJson());
        }
        if (r.url.path.endsWith('/status')) {
          return envelope(trialStatus(denied ? 'retained' : 'trial_active'));
        }
        return failure(403, 'GUEST_TRIAL_EXPIRED', 'trial expired');
      }),
    );
    final auth = AuthProvider(
      authService: AuthService(apiClient: api, tokenStorage: store),
    );
    await auth.initialize();
    final refreshed = Completer<void>();
    auth.addListener(() {
      if (auth.trial?.dataState == 'retained' &&
          !auth.trialLoading &&
          !refreshed.isCompleted) {
        refreshed.complete();
      }
    });
    denied = true;
    await expectLater(
      api.get('/users/bootstrap'),
      throwsA(
        isA<ForbiddenException>().having(
          (e) => e.code,
          'code',
          'GUEST_TRIAL_EXPIRED',
        ),
      ),
    );
    await refreshed.future;
    expect(auth.isAuthenticated, true);
    expect(store.refreshToken, 'refresh');
    auth.dispose();
    api.dispose();
  });
  for (final cookie in [false, true]) {
    for (final operation in ['convert', 'discard', 'replace']) {
      for (final denied in [false, true]) {
        test(
          '${cookie ? 'web cookie' : 'native'} $operation refresh ${denied ? 'denied' : 'accepted'} preserves the pinned operation',
          () async {
            final requests = <http.Request>[];
            var attempts = 0;
            final endpoint = operation == 'convert'
                ? '/convert-guest'
                : operation == 'discard'
                ? '/discard'
                : '/guest';
            final store = MemoryTokenStore()
              ..accessToken = 'expired'
              ..refreshToken = 'refresh';
            final api = ApiClient(
              tokenStorage: store,
              useRefreshCookie: cookie,
              client: MockClient((r) async {
                requests.add(r);
                if (r.url.path.endsWith('/me')) {
                  return envelope(testUser(guest: true).toJson());
                }
                if (r.url.path.endsWith('/status')) {
                  return envelope(trialStatus('retained', eligible: true));
                }
                if (r.url.path.endsWith('/refresh')) {
                  return denied
                      ? failure(401, 'AUTH_SESSION_INVALID', 'revoked')
                      : envelope({
                          'accessToken': 'renewed',
                          'refreshToken': 'rotated',
                        });
                }
                expect(r.url.path.endsWith(endpoint), true);
                if (++attempts == 1) {
                  return failure(401, 'AUTH_TOKEN_EXPIRED', 'expired access');
                }
                expect(r.headers['Authorization'], 'Bearer renewed');
                return operation == 'convert'
                    ? envelope({
                        'user': testUser().toJson(),
                        'loginRequired': true,
                      })
                    : operation == 'discard'
                    ? envelope({'discarded': true})
                    : envelope({
                        'user': testUser(guest: true).toJson(),
                        'tokens': {
                          'accessToken': 'fresh',
                          'refreshToken': 'fresh-refresh',
                        },
                      }, 201);
              }),
            );
            final auth = AuthProvider(
              authService: AuthService(apiClient: api, tokenStorage: store),
            );
            await auth.initialize();
            final result = operation == 'convert'
                ? await auth.convertGuest(
                    email: 'fresh@example.test',
                    password: 'Password2026!',
                    displayName: 'Guest',
                  )
                : operation == 'discard'
                ? await auth.discardGuest()
                : await auth.replaceGuest();
            expect(result, !denied);
            final mutations = requests
                .where((r) => r.url.path.endsWith(endpoint))
                .toList();
            expect(mutations.length, denied ? 1 : 2);
            expect(
              requests.where((r) => r.url.path.endsWith('/refresh')).length,
              1,
            );
            expect(
              requests.where((r) => r.url.path.contains('logout')),
              isEmpty,
            );
            if (!denied) {
              expect(mutations.last.body, mutations.first.body);
              if (operation == 'replace') {
                final body = jsonDecode(mutations.last.body) as Map;
                expect(body['expectedLastGrantAt'], '2026-11-14T23:55:00.123Z');
                expect(body['expectedDataVersion'], 7);
                expect(body['requestKey'], matches(RegExp(r'^[a-f0-9]{64}$')));
              }
            } else {
              expect(store.accessToken, isNull);
              expect(store.refreshToken, isNull);
              expect(auth.isAuthenticated, false);
            }
            auth.dispose();
            api.dispose();
          },
        );
      }
    }
  }
  for (final rejection in [403, 409]) {
    test(
      'conversion $rejection is a definitive rejection and retains guest credentials',
      () async {
        final store = MemoryTokenStore()
          ..accessToken = 'guest'
          ..refreshToken = 'refresh';
        final api = ApiClient(
          tokenStorage: store,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/me')) {
              return envelope(testUser(guest: true).toJson());
            }
            if (r.url.path.endsWith('/status')) {
              return envelope(trialStatus('retained'));
            }
            return failure(
              rejection,
              rejection == 403 ? 'GUEST_DATA_EXPIRED' : 'GUEST_DATA_CHANGED',
              'rejected',
            );
          }),
        );
        final auth = AuthProvider(
          authService: AuthService(apiClient: api, tokenStorage: store),
        );
        await auth.initialize();
        expect(
          await auth.convertGuest(
            email: 'g@example.test',
            password: 'Password2026!',
            displayName: 'Guest',
          ),
          false,
        );
        expect(auth.isAuthenticated, true);
        expect(auth.conversionNeedsLogin, false);
        expect(store.refreshToken, 'refresh');
        auth.dispose();
        api.dispose();
      },
    );
  }
  for (final reconciled in ['guest', 'denied', 'offline']) {
    test(
      'lost conversion reconciles $reconciled without replay or an invented success',
      () async {
        var submitted = false, submits = 0;
        final store = MemoryTokenStore()
          ..accessToken = 'guest'
          ..refreshToken = 'refresh';
        final api = ApiClient(
          tokenStorage: store,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/me')) {
              if (submitted && reconciled == 'offline') {
                throw http.ClientException('offline');
              }
              if (submitted && reconciled == 'denied') {
                return failure(401, 'AUTH_SESSION_INVALID', 'revoked');
              }
              return envelope(testUser(guest: true).toJson());
            }
            if (r.url.path.endsWith('/status')) {
              return envelope(trialStatus('retained'));
            }
            expect(r.url.path.endsWith('/convert-guest'), true);
            submitted = true;
            submits++;
            throw http.ClientException('lost');
          }),
        );
        final auth = AuthProvider(
          authService: AuthService(apiClient: api, tokenStorage: store),
        );
        await auth.initialize();
        expect(
          await auth.convertGuest(
            email: 'g@example.test',
            password: 'Password2026!',
            displayName: 'Guest',
          ),
          false,
        );
        expect(submits, 1);
        expect(auth.conversionNeedsLogin, reconciled == 'denied');
        expect(auth.isAuthenticated, reconciled != 'denied');
        expect(store.refreshToken, reconciled == 'denied' ? isNull : 'refresh');
        auth.dispose();
        api.dispose();
      },
    );
  }
  for (final desktop in [false, true]) {
    for (final stateName in ['retained', 'expired', 'legacy_unknown']) {
      for (final route in ['S10', 'S25']) {
        testWidgets(
          'P4 ${desktop ? 'web' : 'mobile'} $stateName $route bypasses denied bootstrap with RS1 logout',
          (tester) async {
            tester.view.physicalSize = desktop
                ? const Size(1280, 900)
                : const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final paths = <String>[];
            final store = MemoryTokenStore()..accessToken = 'guest';
            final api = ApiClient(
              tokenStorage: store,
              client: MockClient((r) async {
                paths.add(r.url.path);
                if (r.url.path.endsWith('/me')) {
                  return envelope(testUser(guest: true).toJson());
                }
                if (r.url.path.endsWith('/status')) {
                  return envelope(trialStatus(stateName, eligible: true));
                }
                if (r.url.path.endsWith('/bootstrap')) {
                  return failure(403, 'GUEST_TRIAL_EXPIRED', 'trial expired');
                }
                return envelope({'items': [], 'total': 0});
              }),
            );
            final auth = AuthProvider(
              authService: AuthService(apiClient: api, tokenStorage: store),
            );
            await auth.initialize();
            final state = AppState(
              service: StartupUserDataService(apiClient: api),
            );
            await tester.pumpWidget(
              SignVoiceApp(
                auth: auth,
                state: state,
                initialScreen: route,
                webRouting: desktop,
                learningService: DemoLearningService(),
                adminService: DemoDictionaryService(),
              ),
            );
            await tester.pumpAndSettle();
            expect(paths.where((p) => p.endsWith('/bootstrap')), isNotEmpty);
            expect(state.ready, false);
            expect(find.byKey(const ValueKey('guest-discard')), findsOneWidget);
            expect(
              find.byKey(const ValueKey('guest-convert')),
              stateName == 'expired' ? findsNothing : findsOneWidget,
            );
            final logout = find.byKey(const ValueKey('guest-logout'));
            await tester.ensureVisible(logout);
            await tester.tap(logout);
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.textContaining('Bạn không thể quay lại'),
              ),
              findsOneWidget,
            );
            if (stateName == 'legacy_unknown') {
              expect(
                find.textContaining('không thể hẹn ngày dọn dữ liệu'),
                findsOneWidget,
              );
              expect(find.textContaining('24 giờ'), findsNothing);
            }
            await tester.tap(find.text('Ở lại'));
            await tester.pumpAndSettle();
            expect(paths.where((p) => p.endsWith('/logout')), isEmpty);
            expect(auth.isAuthenticated, true);
            await tester.pumpWidget(const SizedBox());
            auth.dispose();
            state.dispose();
            api.dispose();
          },
        );
      }
    }
  }
}
