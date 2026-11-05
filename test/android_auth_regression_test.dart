import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/core/password_reset_link.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/features/library/library_screens.dart';
import 'package:sign_voice/features/profile/profile_screens.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_exception.dart';

import 'auth_fixtures.dart';

class RetryAuth extends FakeAuthService {
  Completer<void>? pending;
  bool reject = true;
  @override
  Future<UserModel?> restoreSession() async => null;
  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    await pending?.future;
    if (reject) throw ApiException(message: 'Mật khẩu không đúng.');
    return testUser();
  }
}

void main() {
  for (final start in ['S05', 'S25']) {
    testWidgets(
      'US_004_002 preserves form while pending and after failure from $start',
      (tester) async {
        final service = RetryAuth();
        final auth = AuthProvider(authService: service);
        await auth.initialize();
        final state = AppState();
        await tester.pumpWidget(
          SignVoiceApp(auth: auth, state: state, initialScreen: start),
        );
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'user@example.com');
        await tester.enterText(fields.at(1), 'WrongPassword2026');
        service.pending = Completer<void>();
        await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
        await tester.tap(find.byKey(const ValueKey('auth-submit')));
        await tester.pump();
        expect(fields, findsNWidgets(2));
        service.pending!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Mật khẩu không đúng.'), findsOneWidget);
        final edits = tester
            .widgetList<TextField>(find.byType(TextField))
            .toList();
        expect(edits[0].controller!.text, 'user@example.com');
        expect(edits[1].controller!.text, 'WrongPassword2026');
        service.reject = false;
        service.pending = null;
        await tester.enterText(fields.at(1), 'CorrectPassword2026');
        await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
        await tester.tap(find.byKey(const ValueKey('auth-submit')));
        await tester.pumpAndSettle();
        expect(auth.isAuthenticated, isTrue);
        if (start == 'S25') expect(find.byType(ProfileScreen), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        state.dispose();
      },
    );
  }
  for (final target in ['S25', 'S24', 'S20']) {
    testWidgets(
      'US_002_004 guest returns to $target, Back and failed retry preserve destination',
      (tester) async {
        final service = RetryAuth();
        final auth = AuthProvider(authService: service);
        await auth.loginAsGuest();
        final state = AppState();
        await tester.pumpWidget(
          SignVoiceApp(
            auth: auth,
            state: state,
            adminService: DemoDictionaryService(),
            initialScreen: target,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Đăng nhập'));
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<AuthScreen>(find.byType(AuthScreen)).returnRoute,
          target,
        );
        await tester.tap(find.byTooltip('Quay lại'));
        await tester.pumpAndSettle();
        expect(find.text('Cần tài khoản cá nhân'), findsOneWidget);
        expect(auth.user!.isGuest, isTrue);
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'user@example.com');
        await tester.enterText(fields.at(1), 'WrongPassword2026');
        await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
        await tester.tap(find.byKey(const ValueKey('auth-submit')));
        await tester.pumpAndSettle();
        expect(find.text('Mật khẩu không đúng.'), findsOneWidget);
        expect(
          tester.widget<AuthScreen>(find.byType(AuthScreen)).returnRoute,
          target,
        );
        service.reject = false;
        await tester.enterText(fields.at(1), 'CorrectPassword2026');
        await tester.ensureVisible(find.byKey(const ValueKey('auth-submit')));
        await tester.tap(find.byKey(const ValueKey('auth-submit')));
        await tester.pumpAndSettle();
        expect(auth.user!.isGuest, isFalse);
        if (target == 'S25') expect(find.byType(ProfileScreen), findsOneWidget);
        if (target == 'S24') {
          expect(
            tester
                .widget<DictionaryScreen>(find.byType(DictionaryScreen))
                .favoritesOnly,
            isTrue,
          );
        }
        if (target == 'S20') expect(find.byType(HistoryScreen), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        state.dispose();
      },
    );
  }
  test(
    'reset platform bridge validates only internal, single-token routes',
    () {
      final token = 'a' * 64;
      expect(
        validatedPasswordResetRoute('/reset-password?token=$token'),
        '/reset-password?token=$token',
      );
      for (final route in [
        '/profile',
        'https://evil.test/reset-password?token=$token',
        '//evil.test/reset-password?token=$token',
        '/reset-password?token=$token&token=$token',
        '/reset-password?token=$token&next=/admin',
        '/reset-password?token=bad',
      ]) {
        expect(validatedPasswordResetRoute(route), isNull);
      }
    },
  );
  testWidgets(
    'warm Android reset intent opens reset form and rejects unrelated routes',
    (tester) async {
      final auth = AuthProvider(authService: RetryAuth());
      await auth.initialize();
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(auth: auth, state: state, initialScreen: 'S05'),
      );
      await tester.pumpAndSettle();
      const channel = MethodChannel('signvoice/auth-links');
      Future<void> send(String route) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('open', route),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await send('/admin');
      expect(find.byType(ResetPasswordScreen), findsNothing);
      await send('/reset-password?token=${'a' * 64}');
      expect(find.byType(ResetPasswordScreen), findsOneWidget);
      expect(find.text('Tạo mật khẩu mới'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );
}
