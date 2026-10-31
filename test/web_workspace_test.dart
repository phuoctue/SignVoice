import 'package:flutter/foundation.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/core/theme.dart';
import 'package:sign_voice/features/auth/web_auth_layout.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/widgets/web_workspace.dart';

import 'auth_fixtures.dart';

void main() {
  for (final dark in [false, true]) {
    for (final size in [const Size(900, 600), const Size(1440, 900)]) {
      testWidgets('auth panel scrolls at $size dark=$dark with enlarged text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var switched = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: makeTheme(dark: dark, highContrast: false),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: WebAuthLayout(
                register: true,
                busy: false,
                onSwitch: () => switched = true,
                form: Column(
                  children: [
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: TextFormField(
                          decoration: InputDecoration(
                            labelText: 'Thông tin tài khoản $i',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final switchButton = find.text('Tôi đã có tài khoản').last;
        await tester.ensureVisible(switchButton);
        await tester.pumpAndSettle();
        await tester.tap(switchButton);
        expect(switched, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final role in [UserRole.user, UserRole.staff]) {
    testWidgets('desktop sidebar navigates and respects $role', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider(role: role);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(
            home: AppScope(
              state: AppState(),
              child: const Scaffold(
                body: WebWorkspace(child: Text('Nội dung')),
              ),
            ),
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(body: Text('Trang ${settings.name}')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 100));
      await mouse.moveTo(const Offset(40, 100));
      await tester.tap(find.byTooltip('Mở thanh điều hướng'));
      await tester.pumpAndSettle();
      if (role == UserRole.staff) {
        await tester.scrollUntilVisible(
          find.text('Quản trị'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
      }
      expect(
        find.text('Quản trị'),
        role == UserRole.staff ? findsOneWidget : findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('Thư viện ký hiệu'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Thư viện ký hiệu'));
      await tester.pumpAndSettle();
      expect(find.text('Trang /dictionary'), findsOneWidget);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'browser owns viewport and switches to compact navigation on resize',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        SignVoiceApp(
          initialScreen: 'S08',
          state: AppState(),
          auth: auth,
          adminService: DemoDictionaryService(),
          learningService: DemoLearningService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WebWorkspace), findsOneWidget);
      expect(
        tester.getSize(find.byType(Scaffold).first).width,
        greaterThan(1000),
      );
      expect(find.byType(NavigationBar), findsNothing);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(WebWorkspace), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !kIsWeb,
  );
}
