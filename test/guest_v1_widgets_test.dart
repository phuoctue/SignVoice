import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/auth/auth_service.dart';
import 'package:sign_voice/widgets/guest_data_panel.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/app.dart';

import 'auth_fixtures.dart';
import 'guest_v1_service_test.dart' show envelope, trialStatus;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'expired session explains unavailable recovery on the actual login route',
    (tester) async {
      final store = MemoryTokenStore()..accessToken = 'guest';
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient(
          (r) async => r.url.path.endsWith('/providers')
              ? envelope({'google': false, 'facebook': false})
              : http.Response('{"error":{"code":"AUTH_SESSION_INVALID"}}', 401),
        ),
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
            child: const MaterialApp(home: AccessGate(screenId: 'S10')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('không thể xác minh quyền'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
      state.dispose();
    },
  );
  testWidgets(
    'dated banner cannot be dismissed and uses the earlier session cutoff for conversion',
    (tester) async {
      final store = MemoryTokenStore()..accessToken = 'guest';
      final cutoff = DateTime.parse('2026-11-14T23:59:00Z');
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient(
          (r) async => envelope(
            r.url.path.endsWith('/me')
                ? testUser(guest: true)
                      .copyWith(legacyGuestSessionCutoffAt: cutoff)
                      .toJson()
                : trialStatus('trial_active'),
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
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: GuestDataPanel(compact: true)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(auth.conversionDeadline, cutoff);
      expect(find.text('Ẩn nhắc nhở'), findsNothing);
      expect(find.textContaining('Hạn chuyển tài khoản'), findsOneWidget);
      expect(find.byKey(const ValueKey('guest-convert')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    },
  );
  testWidgets(
    'discard acknowledgement stays visible when the access gate switches to login',
    (tester) async {
      final store = MemoryTokenStore()..accessToken = 'guest';
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/me')) {
            return envelope(testUser(guest: true).toJson());
          }
          if (r.url.path.endsWith('/providers')) {
            return envelope({'google': false, 'facebook': false});
          }
          if (r.method == 'POST') return envelope({'discarded': true});
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
            child: const MaterialApp(home: AccessGate(screenId: 'S10')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('guest-discard'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guest-confirm-loss')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Đã xóa dữ liệu khách'), findsOneWidget);
      expect(auth.errorMessage, isNull);
      expect(find.textContaining('Phiên đăng nhập đã hết hạn'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
      state.dispose();
    },
  );
  for (final desktop in [false, true]) {
    for (final replace in [false, true]) {
      testWidgets(
        '${desktop ? 'web' : 'Android'} ${replace ? 'replacement' : 'discard'} needs separate consent and cancel changes nothing',
        (tester) async {
          tester.view.physicalSize = desktop
              ? const Size(1280, 900)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var writes = 0;
          final store = MemoryTokenStore()..accessToken = 'guest';
          final api = ApiClient(
            tokenStorage: store,
            client: MockClient((r) async {
              if (r.method == 'POST') {
                writes++;
                return envelope({'discarded': true});
              }
              return envelope(
                r.url.path.endsWith('/me')
                    ? testUser(guest: true).toJson()
                    : trialStatus('retained', eligible: true),
              );
            }),
          );
          final auth = AuthProvider(
            authService: AuthService(apiClient: api, tokenStorage: store),
          );
          await auth.initialize();
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: MaterialApp(
                theme: ThemeData(
                  platform: desktop
                      ? TargetPlatform.windows
                      : TargetPlatform.android,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: SingleChildScrollView(child: GuestDataPanel()),
                ),
              ),
            ),
          );
          final button = find.byKey(
            ValueKey(replace ? 'guest-replace' : 'guest-discard'),
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(find.textContaining('Không thể hoàn tác'), findsOneWidget);
          expect(writes, 0);
          if (desktop) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.tap(find.text('Hủy'));
          }
          await tester.pumpAndSettle();
          expect(writes, 0);
          expect(auth.isAuthenticated, true);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          auth.dispose();
          api.dispose();
        },
      );
    }
    for (final status in [401, 403, 409, 429, 500]) {
      testWidgets(
        '${desktop ? 'web' : 'Android'} status $status never exposes mutation actions or fakes success',
        (tester) async {
          tester.view.physicalSize = desktop
              ? const Size(1280, 900)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = MemoryTokenStore()..accessToken = 'guest';
          final paths = <String>[];
          final api = ApiClient(
            tokenStorage: store,
            client: MockClient((r) async {
              paths.add(r.method);
              if (r.url.path.endsWith('/me')) {
                return envelope(testUser(guest: true).toJson());
              }
              return http.Response(
                '{"error":{"code":"AUTH_SESSION_INVALID","message":"fixture error"}}',
                status,
              );
            }),
          );
          final auth = AuthProvider(
            authService: AuthService(apiClient: api, tokenStorage: store),
          );
          await auth.initialize();
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: MaterialApp(
                theme: ThemeData(
                  platform: desktop
                      ? TargetPlatform.windows
                      : TargetPlatform.android,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: SingleChildScrollView(child: GuestDataPanel()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final key in [
            'guest-convert',
            'guest-discard',
            'guest-replace',
          ]) {
            expect(find.byKey(ValueKey(key)), findsNothing);
          }
          expect(find.textContaining('Đã xóa'), findsNothing);
          expect(paths.every((m) => m == 'GET'), true);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          auth.dispose();
          api.dispose();
        },
      );
    }
    testWidgets(
      '${desktop ? 'web' : 'Android'} logout warns about lost access and registration, default cancel sends nothing',
      (tester) async {
        tester.view.physicalSize = desktop
            ? const Size(1280, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryTokenStore()..accessToken = 'guest';
        final api = ApiClient(
          tokenStorage: store,
          client: MockClient(
            (r) async => envelope(
              r.url.path.endsWith('/me')
                  ? testUser(guest: true).toJson()
                  : trialStatus('retained'),
            ),
          ),
        );
        final auth = AuthProvider(
          authService: AuthService(apiClient: api, tokenStorage: store),
        );
        await auth.initialize();
        bool? result;
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: auth,
            child: MaterialApp(
              theme: ThemeData(
                platform: desktop
                    ? TargetPlatform.windows
                    : TargetPlatform.android,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await confirmGuestLogout(context);
                    },
                    child: const Text('Thoát'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Thoát'));
        await tester.pumpAndSettle();
        expect(find.textContaining('không thể quay lại'), findsOneWidget);
        expect(find.textContaining('24 giờ'), findsOneWidget);
        expect(find.text('Đăng ký để giữ dữ liệu'), findsOneWidget);
        await tester.tap(find.text('Ở lại'));
        await tester.pumpAndSettle();
        expect(result, false);
        expect(auth.isAuthenticated, true);
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        api.dispose();
      },
    );
    for (final state in [
      'trial_active',
      'retained',
      'cooldown_elapsed',
      'expired',
      'legacy_unknown',
      'offline',
      'loading',
    ]) {
      testWidgets(
        '${desktop ? 'web keyboard' : 'Android semantics'} $state at 200% fits and follows server actions',
        (tester) async {
          tester.view.physicalSize = desktop
              ? const Size(1280, 900)
              : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          final requests = <String>[];
          final pending = Completer<http.Response>();
          var offline = state == 'offline';
          final store = MemoryTokenStore()..accessToken = 'guest';
          final api = ApiClient(
            tokenStorage: store,
            client: MockClient((r) async {
              requests.add('${r.method} ${r.url.path}');
              if (r.url.path.endsWith('/me')) {
                return envelope(testUser(guest: true).toJson());
              }
              if (state == 'loading') return pending.future;
              if (offline) throw http.ClientException('offline');
              return envelope(
                trialStatus(
                  state == 'cooldown_elapsed' ? 'retained' : state,
                  eligible: state == 'cooldown_elapsed',
                ),
              );
            }),
          );
          final auth = AuthProvider(
            authService: AuthService(apiClient: api, tokenStorage: store),
          );
          final initialized = auth.initialize();
          if (state != 'loading') await initialized;
          // Loading is exercised on an already restored user, while status is pending.
          if (state == 'loading') {
            await tester.pump();
          }
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: MaterialApp(
                theme: ThemeData(
                  platform: desktop
                      ? TargetPlatform.windows
                      : TargetPlatform.android,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: SingleChildScrollView(child: GuestDataPanel()),
                ),
              ),
            ),
          );
          await tester.pump();
          if (state != 'loading') await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final canConvert = !['expired', 'offline', 'loading'].contains(state);
          expect(
            find.byKey(const ValueKey('guest-convert')),
            canConvert ? findsOneWidget : findsNothing,
          );
          if (canConvert) {
            expect(
              tester
                  .getSemantics(find.byKey(const ValueKey('guest-convert')))
                  .getSemanticsData()
                  .label,
              contains('Đăng ký tài khoản mới để giữ dữ liệu'),
            );
          }
          expect(
            find.byKey(const ValueKey('guest-discard')),
            ['offline', 'loading'].contains(state)
                ? findsNothing
                : findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('guest-replace')),
            state == 'cooldown_elapsed' ? findsOneWidget : findsNothing,
          );
          if (desktop) {
            final order = state == 'loading'
                ? ['guest-login']
                : state == 'offline'
                ? ['guest-retry']
                : [
                    'guest-refresh',
                    canConvert ? 'guest-convert' : 'guest-register-fresh',
                  ];
            for (final key in order) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pump();
              final focused =
                  FocusManager.instance.primaryFocus!.context!.widget;
              expect(
                find.ancestor(
                  of: find.byWidget(focused),
                  matching: find.byKey(ValueKey(key)),
                ),
                findsOneWidget,
              );
            }
            final beforeEscape = requests.length;
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pump();
            expect(requests.length, beforeEscape);
            expect(find.byType(GuestDataPanel), findsOneWidget);
          }
          if (state == 'offline') {
            offline = false;
            await tester.ensureVisible(find.text('Thử lại'));
            await tester.tap(find.text('Thử lại'));
            await tester.pumpAndSettle();
          }
          expect(requests.every((r) => r.startsWith('GET ')), true);
          if (state == 'loading') {
            pending.complete(envelope(trialStatus('retained')));
            await initialized;
            await tester.pumpAndSettle();
          }
          await tester.pumpWidget(const SizedBox());
          auth.dispose();
          api.dispose();
          semantics.dispose();
        },
      );
    }
  }
  testWidgets(
    'expired guest ordinary registration must not submit a forbidden conversion',
    (tester) async {
      final store = MemoryTokenStore()..accessToken = 'guest';
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient(
          (r) async => envelope(
            r.url.path.endsWith('/me')
                ? testUser(guest: true).toJson()
                : r.url.path.endsWith('/providers')
                ? {'google': false, 'facebook': false}
                : trialStatus('expired'),
          ),
        ),
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
      expect(find.text('Chuyển thành tài khoản'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
      state.dispose();
    },
  );
}
