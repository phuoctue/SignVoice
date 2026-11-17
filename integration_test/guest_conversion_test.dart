import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_config.dart';
import 'package:sign_voice/services/auth/auth_service.dart';
import 'package:sign_voice/services/user/user_data_service.dart';
import 'package:sign_voice/widgets/guest_data_panel.dart';

import '../test/auth_fixtures.dart' show MemoryTokenStore;

// Only guest_loopback_backend.cjs; Android uses adb reverse for the same URL.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final origin = Uri.parse(ApiConfig.baseUrl).origin;
  if (!['http://127.0.0.1:39147', 'http://localhost:39147'].contains(origin)) {
    throw StateError('Use the disposable loopback fixture on port 39147.');
  }
  Future<Map<String, dynamic>> check(String id) async =>
      Map<String, dynamic>.from(
        jsonDecode(
          (await http.get(Uri.parse('$origin/__fixture/check/$id'))).body,
        ),
      );
  Future<void> seed(String id) async {
    final result = await http.post(
      Uri.parse('$origin/__fixture/seed'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': id}),
    );
    expect(result.statusCode, 200);
  }

  testWidgets(
    'real backend: guest data survives same-ID conversion and subsequent login',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = MemoryTokenStore();
      final api = ApiClient(tokenStorage: store, useRefreshCookie: false);
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      final state = AppState();
      final data = UserDataService(apiClient: api);
      expect(await auth.loginAsGuest(), true);
      final owner = auth.user!.id;
      await seed(owner);
      final before = await data.conversations();
      expect((before['items'] as List).length, 1);
      await auth.loadGuestTrial();
      expect(auth.trialError, isNull, reason: auth.trialError);
      expect(auth.trial?.allows('convert'), true);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: AppScope(
            state: state,
            child: MaterialApp(
              routes: {
                'S08': (_) => const Scaffold(body: Text('Đã đăng nhập')),
              },
              home: const AuthScreen(register: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('guest-v1-convert');
      // Expire the access token while this form stays open; refresh must precede conversion.
      expect(
        (await http.post(
          Uri.parse('$origin/__fixture/advance'),
          headers: {'Content-Type': 'application/json'},
          body: '{"minutes":16}',
        )).statusCode,
        200,
      );
      final email =
          'flutter-${DateTime.now().microsecondsSinceEpoch}@example.test';
      final fields = find.byType(TextFormField);
      for (var i = 0; i < 4; i++) {
        await tester.ensureVisible(fields.at(i));
        await tester.enterText(
          fields.at(i),
          ['Người dùng', email, 'Lifecycle2026!', 'Lifecycle2026!'][i],
        );
      }
      await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      for (var i = 0; auth.isLoading && i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(auth.isAuthenticated, false);
      expect(find.textContaining('thành công'), findsOneWidget);
      expect((await check(owner))['conversations'], 1);
      expect(await auth.login(email: email, password: 'Lifecycle2026!'), true);
      expect(auth.user!.id, owner);
      expect(await data.conversations(), before);
      await binding.takeScreenshot('guest-v1-login-data-preserved');
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
      state.dispose();
    },
  );
  testWidgets(
    'real backend: separately confirmed discard deletes only the guest and preserves cooldown',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = MemoryTokenStore();
      final api = ApiClient(tokenStorage: store, useRefreshCookie: false);
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      expect(await auth.loginAsGuest(), true);
      final owner = auth.user!.id;
      await seed(owner);
      await auth.loadGuestTrial();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: GuestDataPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final discard = find.byKey(const ValueKey('guest-discard'));
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await tester.ensureVisible(discard);
      await tester.tap(discard);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('guest-v1-discard-confirm');
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect((await check(owner))['userExists'], true);
      await tester.tap(discard);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('guest-confirm-loss')),
      );
      await tester.tap(find.byKey(const ValueKey('guest-confirm-loss')));
      for (
        var i = 0;
        (auth.guestOperationBusy || auth.isAuthenticated) && i < 200;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(auth.guestOperationMessage, contains('Đã xóa'));
      final result = await check(owner);
      expect(result['userExists'], false);
      expect(result['conversations'], 0);
      expect(result['cooldownRows'], greaterThan(0));
      expect(await auth.loginAsGuest(), false);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('guest-v1-discard-acknowledged');
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
    },
  );
  testWidgets(
    'real backend: expired trial reopens through denied bootstrap into data choices',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = MemoryTokenStore();
      final originalApi = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
      );
      final originalAuth = AuthProvider(
        authService: AuthService(apiClient: originalApi, tokenStorage: store),
      );
      expect(await originalAuth.loginAsGuest(), true);
      final owner = originalAuth.user!.id;
      await seed(owner);
      expect(
        (await http.post(
          Uri.parse('$origin/__fixture/advance'),
          headers: {'Content-Type': 'application/json'},
          body: '{"minutes":16}',
        )).statusCode,
        200,
      );
      originalAuth.dispose();
      originalApi.dispose();
      final api = ApiClient(tokenStorage: store, useRefreshCookie: false);
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      await auth.initialize();
      expect(auth.user?.id, owner);
      expect(auth.trial?.dataState, 'retained');
      final state = AppState(service: StartupUserDataService(apiClient: api));
      await tester.pumpWidget(
        SignVoiceApp(auth: auth, state: state, initialScreen: 'S10'),
      );
      for (var i = 0; state.syncing && i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(state.ready, false);
      expect(state.error, isNotNull);
      expect(find.text('Dữ liệu tài khoản'), findsNothing);
      expect(find.byKey(const ValueKey('guest-discard')), findsOneWidget);
      expect(find.byKey(const ValueKey('guest-convert')), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('guest-v1-r1-expired-reopened');
      final logout = find.byKey(const ValueKey('guest-logout'));
      await tester.ensureVisible(logout);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      expect(find.textContaining('Bạn không thể quay lại'), findsOneWidget);
      await tester.tap(find.text('Ở lại'));
      await tester.pumpAndSettle();
      expect(auth.isAuthenticated, true);
      expect((await check(owner))['conversations'], 1);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      api.dispose();
      state.dispose();
    },
  );
}
