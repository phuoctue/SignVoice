import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/features/auth/web_auth_layout.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/auth/auth_service.dart';

import 'auth_fixtures.dart';
import 'guest_conversion_test.dart' show ok, failure;
import 'guest_v1_service_test.dart' show trialStatus;

class GuestHarness {
  GuestHarness({this.convert, this.guestSessionGone = false});
  final bool guestSessionGone;
  Future<http.Response> Function()? convert;
  int submits = 0;
  final paths = <String>[];
  final store = MemoryTokenStore()
    ..accessToken = 'guest'
    ..refreshToken = 'refresh';
  late final api = ApiClient(
    tokenStorage: store,
    useRefreshCookie: false,
    client: MockClient((r) async {
      paths.add(r.url.path);
      if (r.url.path.endsWith('/me')) {
        if (guestSessionGone && submits > 0) {
          return failure(401, 'AUTH_SESSION_INVALID', 'guest session ended');
        }
        return ok(testUser(guest: true).toJson());
      }
      if (r.url.path.endsWith('/convert-guest')) {
        submits++;
        return convert!();
      }
      if (r.url.path.endsWith('/providers')) {
        return ok({'google': false, 'facebook': false});
      }
      return ok(trialStatus('retained'));
    }),
  );
  late final auth = AuthProvider(
    authService: AuthService(apiClient: api, tokenStorage: store),
  );
  final state = AppState();
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
  }) async {
    await auth.initialize();
    auth.acceptRestoredGuest();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: AppScope(
          state: state,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    api.dispose();
    state.dispose();
  }
}

Future<void> fillConversion(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Người dùng');
  await tester.enterText(fields.at(1), 'guest@example.com');
  await tester.enterText(fields.at(2), 'Pass12345');
  await tester.enterText(fields.at(3), 'Pass12345');
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('auth-submit')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  for (final desktop in [false, true]) {
    testWidgets(
      'P5 ${desktop ? 'web' : 'mobile 200%'} keeps conversion copy while submitting',
      (tester) async {
        tester.view.physicalSize = desktop
            ? const Size(1440, 1000)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pending = Completer<http.Response>();
        final h = GuestHarness(convert: () => pending.future);
        await h.mount(
          tester,
          const AuthScreen(register: true),
          scale: desktop ? 1 : 2,
        );
        try {
          final heading = find.text('Chuyển thành tài khoản');
          final ordinary = find.textContaining(
            'Tài khoản mới này không khôi phục hay nhận dữ liệu khách',
          );
          final headingCount = heading.evaluate().length;
          expect(headingCount, greaterThan(0));
          expect(ordinary, findsNothing);
          final fields = find.byType(TextFormField);
          for (var i = 0; i < 4; i++) {
            await tester.enterText(
              fields.at(i),
              ['Người dùng', 'guest@example.com', 'Pass12345', 'Pass12345'][i],
            );
          }
          final button = find.byKey(const ValueKey('auth-submit'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pump(const Duration(milliseconds: 300));
          expect(h.submits, 1);
          expect(h.auth.state, AuthState.loading);
          expect(ordinary, findsNothing);
          expect(heading, findsNWidgets(headingCount));
          expect(find.textContaining('thành công'), findsNothing);
          expect(tester.takeException(), isNull);
          pending.complete(
            ok({'user': testUser().toJson(), 'loginRequired': true}),
          );
          await tester.pumpAndSettle();
          expect(find.byType(TextFormField), findsNWidgets(2));
          expect(heading, findsNothing);
          expect(
            find.textContaining('Chuyển tài khoản thành công'),
            findsOneWidget,
          );
        } finally {
          if (!pending.isCompleted) {
            pending.complete(
              ok({'user': testUser().toJson(), 'loginRequired': true}),
            );
            await tester.pumpAndSettle();
          }
          await h.dispose(tester);
        }
      },
    );
  }
  testWidgets(
    'desktop register form receives pointer activation after sliding right',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var pressed = false;
      final h = GuestHarness();
      await h.mount(
        tester,
        WebAuthLayout(
          register: true,
          busy: false,
          onSwitch: () {},
          form: FilledButton(
            onPressed: () => pressed = true,
            child: const Text('Gửi chuyển tài khoản'),
          ),
        ),
      );
      await tester.tap(find.text('Gửi chuyển tài khoản'));
      await tester.pumpAndSettle();
      expect(pressed, true);
      await h.dispose(tester);
    },
  );
  testWidgets(
    'desktop tall conversion form stays tappable after scrolling at 200%',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var submitted = false;
      final h = GuestHarness();
      await h.mount(
        tester,
        WebAuthLayout(
          register: true,
          busy: false,
          onSwitch: () {},
          form: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 10; i++)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Thông tin tài khoản',
                    ),
                  ),
                ),
              FilledButton(
                key: const ValueKey('tall-submit'),
                onPressed: () => submitted = true,
                child: const Text('Gửi thông tin tài khoản'),
              ),
            ],
          ),
        ),
        scale: 2,
      );
      final button = find.byKey(const ValueKey('tall-submit'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(submitted, true);
      await h.dispose(tester);
    },
  );
  final outcomes = <String, Future<http.Response> Function()>{
    'success': () async =>
        ok({'user': testUser().toJson(), 'loginRequired': true}),
    'conflict': () async =>
        failure(409, 'AUTH_EMAIL_ALREADY_EXISTS', 'Email already registered'),
    'validation': () async =>
        failure(400, 'VALIDATION_ERROR', 'displayName: Invalid name'),
    'rate': () async => failure(429, 'RATE_LIMITED', 'Too many requests'),
    'network': () async => throw http.ClientException('lost response'),
    'timeout': () async => throw TimeoutException('lost response'),
    'converted': () async =>
        failure(400, 'BAD_REQUEST', 'Only guest accounts can be converted'),
    'session': () async =>
        failure(401, 'AUTH_SESSION_INVALID', 'Session changed'),
    'missing-ack': () async => ok({'user': testUser().toJson()}),
    'wrong-status': () async =>
        http.Response('{"success":true,"data":{"loginRequired":true}}', 201),
  };
  for (final scenario in [
    for (final entry in outcomes.entries)
      for (final scale in [1.0, 2.0]) (entry: entry, scale: scale),
  ]) {
    final entry = scenario.entry;
    testWidgets(
      'conversion ${entry.key} scale ${scenario.scale} preserves inputs and reports only acknowledged success',
      (tester) async {
        tester.view.physicalSize = kIsWeb
            ? const Size(1440, 1000)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = GuestHarness(
          convert: entry.value,
          guestSessionGone: [
            'network',
            'timeout',
            'converted',
            'session',
            'missing-ack',
            'wrong-status',
          ].contains(entry.key),
        );
        await h.mount(
          tester,
          const AuthScreen(register: true),
          scale: scenario.scale,
        );
        try {
          expect(find.text('Chuyển thành tài khoản'), findsWidgets);
          expect(find.textContaining('bộ sưu tập'), findsOneWidget);
          await fillConversion(tester);
          expect(tester.takeException(), isNull);
          expect(h.submits, 1);
          expect(
            h.paths.where(
              (p) => p.contains('logout') || p.endsWith('/refresh'),
            ),
            isEmpty,
          );
          final recovery = [
            'network',
            'timeout',
            'converted',
            'session',
            'missing-ack',
            'wrong-status',
          ].contains(entry.key);
          final login = recovery || entry.key == 'success';
          expect(find.byType(TextFormField), findsNWidgets(login ? 2 : 4));
          final fields = tester
              .widgetList<TextFormField>(find.byType(TextFormField))
              .toList();
          expect(fields[login ? 0 : 1].controller!.text, 'guest@example.com');
          expect(fields[login ? 1 : 2].controller!.text, isEmpty);
          if (login) expect(h.store.accessToken, isNull);
          if (recovery) {
            expect(
              find.textContaining('Nếu bạn đã tạo tài khoản'),
              findsOneWidget,
            );
            expect(find.textContaining('thành công'), findsNothing);
          } else if (entry.key == 'success') {
            expect(find.textContaining('thành công'), findsOneWidget);
          } else {
            expect(fields[0].controller!.text, 'Người dùng');
            expect(
              find.textContaining(
                entry.key == 'conflict'
                    ? 'Email đã được dùng'
                    : entry.key == 'rate'
                    ? 'thử lại sau'
                    : 'Tên cần',
              ),
              findsWidgets,
            );
          }
        } catch (error) {
          // ignore: avoid_print
          print('Conversion scenario ${entry.key}/${scenario.scale}: $error');
          rethrow;
        } finally {
          await h.dispose(tester);
        }
      },
    );
  }
  testWidgets('conversion blocks double submit', (tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = Completer<http.Response>();
    final h = GuestHarness(convert: () => pending.future);
    await h.mount(tester, const AuthScreen(register: true));
    final fields = find.byType(TextFormField);
    for (var i = 0; i < 4; i++) {
      await tester.enterText(
        fields.at(i),
        ['Người dùng', 'guest@example.com', 'Pass12345', 'Pass12345'][i],
      );
    }
    final button = find.byKey(const ValueKey('auth-submit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(h.submits, 1);
    pending.complete(ok({'user': testUser().toJson(), 'loginRequired': true}));
    await tester.pumpAndSettle();
    await h.dispose(tester);
  });
}
