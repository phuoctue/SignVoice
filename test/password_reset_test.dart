import 'package:sign_voice/core/app_state.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/auth/auth_service.dart';

import 'auth_fixtures.dart';

void main() {
  testWidgets('forgot password waits for API before showing acknowledgement', (
    tester,
  ) async {
    final completion = Completer<http.Response>();
    final store = MemoryTokenStore();
    final api = ApiClient(
      tokenStorage: store,
      useRefreshCookie: false,
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/auth/forgot-password'));
        expect(jsonDecode(request.body), {'email': 'user@example.com'});
        expect(request.headers.containsKey('Authorization'), isFalse);
        return completion.future;
      }),
    );
    addTearDown(api.dispose);
    final service = AuthService(apiClient: api, tokenStorage: store);
    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordScreen(authService: service)),
    );
    await tester.enterText(find.byType(TextFormField), 'user@example.com');
    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pump();
    expect(find.text('Đang gửi...'), findsOneWidget);
    expect(find.text('Kiểm tra email của bạn'), findsNothing);
    completion.complete(http.Response(jsonEncode({'success': true}), 200));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra email của bạn'), findsOneWidget);
  });

  testWidgets(
    'forgot password shows server error without a false acknowledgement',
    (tester) async {
      final store = MemoryTokenStore();
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'Gửi email chưa khả dụng'},
            }),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ForgotPasswordScreen(
            authService: AuthService(apiClient: api, tokenStorage: store),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'user@example.com');
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();
      expect(find.text('Gửi email chưa khả dụng'), findsOneWidget);
      expect(find.text('Kiểm tra email của bạn'), findsNothing);
    },
  );

  testWidgets(
    'reset validates confirmation then clears local session only after success',
    (tester) async {
      final token = 'a' * 64;
      var requests = 0;
      final store = MemoryTokenStore()
        ..accessToken = 'old-access'
        ..refreshToken = 'old-refresh'
        ..role = 'USER';
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((request) async {
          requests++;
          expect(request.url.path, endsWith('/auth/reset-password'));
          expect(jsonDecode(request.body), {
            'token': token,
            'newPassword': 'NewPassword123',
          });
          return http.Response(jsonEncode({'success': true}), 200);
        }),
      );
      addTearDown(api.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ResetPasswordScreen(
            token: token,
            authService: AuthService(apiClient: api, tokenStorage: store),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'NewPassword123',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Different123');
      await tester.ensureVisible(find.text('Lưu mật khẩu mới'));
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(store.accessToken, 'old-access');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'NewPassword123',
      );
      await tester.ensureVisible(find.text('Lưu mật khẩu mới'));
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(find.text('Đã đổi mật khẩu'), findsOneWidget);
      expect(store.accessToken, isNull);
      expect(api.sessionInvalidated.value, 1);
    },
  );

  testWidgets('email deep link stays on reset page past the splash delay', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/reset-password?token=${'a' * 64}';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final auth = AuthProvider(authService: FakeAuthService());
    addTearDown(auth.dispose);
    await tester.pumpWidget(SignVoiceApp(auth: auth, state: AppState()));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(find.text('Tạo mật khẩu mới'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
