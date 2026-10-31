import 'package:flutter/material.dart';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/core/theme.dart';
import 'package:sign_voice/features/auth/web_auth_layout.dart';

void main() {
  const previewFont = String.fromEnvironment('AUTH_PREVIEW_FONT');
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_AUTH') && previewFont.isNotEmpty) {
      final fonts = FontLoader('AuthPreview');
      fonts.addFont(
        File(previewFont)
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
      await fonts.load();
    }
  });
  for (final reduce in [false, true]) {
    testWidgets('panel slides, reverses and retains fields reduced=$reduce', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduce);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final email = TextEditingController();
      addTearDown(email.dispose);
      final formKey = GlobalKey<FormState>();
      var register = false;
      late StateSetter change;
      var providerCalls = 0;
      final theme = makeTheme(dark: true, highContrast: false);
      await tester.pumpWidget(
        MaterialApp(
          theme:
              const bool.fromEnvironment('CAPTURE_AUTH') &&
                  previewFont.isNotEmpty
              ? theme.copyWith(
                  textTheme: theme.textTheme.apply(fontFamily: 'AuthPreview'),
                )
              : theme,
          home: StatefulBuilder(
            builder: (context, update) {
              change = update;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reduce),
                child: WebAuthLayout(
                  register: register,
                  busy: false,
                  onSwitch: () => update(() => register = !register),
                  form: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          register ? 'Tạo tài khoản' : 'Chào mừng trở lại!',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 24),
                        WebSocialSignIn(
                          busy: false,
                          onGoogle: () => providerCalls++,
                          onFacebook: () => providerCalls++,
                        ),
                        const SizedBox(height: 24),
                        if (register) ...[
                          TextFormField(
                            decoration: const InputDecoration(
                              labelText: 'Họ và tên',
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          key: const ValueKey('email'),
                          controller: email,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu',
                          ),
                        ),
                        if (register) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Xác nhận mật khẩu',
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () {},
                          child: Text(register ? 'Tạo tài khoản' : 'Đăng nhập'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('email')),
        'learner@example.com',
      );
      await tester.tap(find.byTooltip('Tiếp tục với Google'));
      expect(providerCalls, 1);
      final panel = find.byKey(const ValueKey('auth-sliding-panel'));
      final start = tester.getTopLeft(panel).dx;
      final height = tester.getSize(panel).height;
      if (const bool.fromEnvironment('CAPTURE_AUTH') && !reduce) {
        await expectLater(
          find.byType(WebAuthLayout),
          matchesGoldenFile('../.runtime/auth-polished-login.png'),
        );
      }
      await tester.tap(find.text('Tạo tài khoản mới').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      {
        final intermediate = tester.getTopLeft(panel).dx;
        expect(intermediate, lessThan(start));
        expect(intermediate, greaterThan(32));
        expect(find.text('Họ và tên'), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(panel).dx, lessThan(start - 400));
      expect(tester.getSize(panel).height, height);
      expect(find.text('Họ và tên'), findsOneWidget);
      expect(email.text, 'learner@example.com');
      if (const bool.fromEnvironment('CAPTURE_AUTH') && !reduce) {
        await expectLater(
          find.byType(WebAuthLayout),
          matchesGoldenFile('../.runtime/auth-polished-register.png'),
        );
      }
      // Reverse an unfinished transition; no duplicate Form/global key or ticker.
      await tester.tap(find.text('Tôi đã có tài khoản').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      change(() => register = true);
      await tester.pumpAndSettle();
      expect(find.text('Họ và tên'), findsOneWidget);
      expect(email.text, 'learner@example.com');
      expect(find.byType(Form), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
