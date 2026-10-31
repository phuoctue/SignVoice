import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/widgets/public_sign_preview.dart';
import 'package:sign_voice/features/auth/landing_hero_demo.dart';
import 'package:sign_voice/features/auth/landing_motion.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/core/navigation.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/features/library/library_screens.dart';
import 'package:sign_voice/widgets/public_catalog_page.dart';

import 'auth_fixtures.dart';

class LandingLearningService extends DemoLearningService {
  @override
  Future<LearningRecord> collectionRead(
    String path, {
    int page = 1,
    String search = '',
  }) async => {
    'items': [],
    'pagination': {'total': 12, 'pages': 1, 'page': 1},
  };
}

class LandingDictionaryService extends DemoDictionaryService {
  bool fail = false;
  final calls = <String>[];
  @override
  Future<AdminPageData> published({
    int page = 1,
    String search = '',
    String? categoryId,
    String sort = 'word_asc',
  }) async {
    calls.add(search);
    if (fail) throw StateError('offline');
    return AdminPageData(
      [
        {
          '_id': 'one',
          'word': search.isEmpty ? 'chào' : search,
          'definition': 'Mẫu ký hiệu công khai',
        },
        if (search.isEmpty) {'_id': 'two', 'word': 'cảm ơn'},
      ],
      1,
      5,
      97,
    );
  }
}

class PublicCollectionPreviewFixture extends LandingLearningService {
  @override
  Future<LearningRecord> collectionRead(
    String path, {
    int page = 1,
    String search = '',
  }) async => path.startsWith('/shared-collections/')
      ? {
          'collection': {
            'name': 'Bộ sưu tập fixture',
            'description': 'Dữ liệu kiểm thử',
          },
          'items': [],
          'pagination': {'page': 1, 'pages': 1, 'total': 0},
        }
      : await super.collectionRead(path, page: page, search: search);
}

Future<void> settleLanding(WidgetTester tester) async {
  await tester.pump();
  final motion = find.byTooltip('Giảm chuyển động');
  if (motion.evaluate().isNotEmpty) {
    await tester.tap(motion);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'public shared preview returns to discovery at 375px and text 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final auth = AuthProvider(authService: FakeAuthService());
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/collections/shared/dddddddddddddddddddddddddddddddd',
          auth: auth,
          state: state,
          adminService: DemoDictionaryService(),
          learningService: PublicCollectionPreviewFixture(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PublicCatalogPage), findsOneWidget);
      expect(find.text('Bộ sưu tập fixture'), findsOneWidget);
      final back = find.widgetWithText(TextButton, 'Bộ sưu tập công khai');
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Tìm bộ công khai'), findsOneWidget);
      expect(auth.isAuthenticated, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );
  testWidgets(
    'public collections use the public header and brand returns home',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final auth = AuthProvider(authService: FakeAuthService());
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/collections/discover',
          auth: auth,
          state: state,
          adminService: DemoDictionaryService(),
          learningService: LandingLearningService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PublicCatalogPage), findsOneWidget);
      expect(find.text('Tìm bộ công khai'), findsOneWidget);
      expect(find.text('Đăng nhập'), findsOneWidget);
      await tester.tap(find.byType(PublicHeaderBrand));
      await settleLanding(tester);
      expect(find.byType(WebLandingPage), findsOneWidget);
      expect(auth.isAuthenticated, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );
  for (final width in [375.0, 1440.0]) {
    testWidgets(
      'portal starts closed and panels reveal fixture media at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LandingPortal(
                hero: true,
                child: const SizedBox(
                  height: 270,
                  width: double.infinity,
                  child: Text('Fixture media'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(LandingPortal)).width, width);
        expect(find.text('Sign'), findsOneWidget);
        expect(find.text('Voice'), findsOneWidget);
        final left = find.byKey(const ValueKey('portal-panel-left'));
        expect(tester.widget<Transform>(left).transform.storage[12], 0);
        expect(find.byKey(const ValueKey('portal-open')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('portal-open')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<Transform>(left).transform.storage[12],
          lessThan(0),
        );
        await tester.pumpAndSettle();
        expect(left, findsNothing);
        expect(find.text('Fixture media'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('portal reduced motion is open without scheduling animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const Scaffold(
            body: LandingPortal(
              child: SizedBox(
                height: 270,
                width: 375,
                child: Text('Fixture media'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('portal-open')), findsNothing);
    expect(find.byKey(const ValueKey('portal-panel-left')), findsNothing);
    expect(tester.binding.hasScheduledFrame, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final viaSignal in [true, false]) {
    testWidgets('portal opens via ${viaSignal ? 'CTA signal' : 'scroll'}', (
      tester,
    ) async {
      final scroll = ScrollController(), signal = ValueNotifier<int>(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  LandingPortal(
                    scroll: scroll,
                    signal: signal,
                    child: const SizedBox(height: 270, width: 375),
                  ),
                  const SizedBox(height: 1400),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('portal-open')), findsOneWidget);
      if (viaSignal) {
        signal.value++;
      } else {
        scroll.jumpTo(70);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('portal-panel-left')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      signal.dispose();
    });
  }
  testWidgets(
    'mercury CTA supports keyboard Enter and Space with a 48px target',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LandingCta(label: 'Fixture CTA', onPressed: () => calls++),
          ),
        ),
      );
      final button = find.widgetWithText(FilledButton, 'Fixture CTA');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    for (final contrast in [false, true]) {
      testWidgets(
        'liquid landing preserves theme dark=$dark contrast=$contrast',
        (tester) async {
          tester.view.physicalSize = const Size(1024, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final state = AppState()
            ..themeMode = dark ? ThemeMode.dark : ThemeMode.light
            ..highContrast = contrast;
          final auth = AuthProvider(authService: FakeAuthService());
          await tester.pumpWidget(
            SignVoiceApp(
              webRouting: true,
              initialScreen: '/home',
              state: state,
              auth: auth,
              adminService: LandingDictionaryService(),
              learningService: LandingLearningService(),
            ),
          );
          await settleLanding(tester);
          // App bootstrap restores preferences; apply the fixture after it finishes.
          state.update(() {
            state.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
            state.highContrast = contrast;
          });
          await settleLanding(tester);
          final hero = tester.element(find.byType(LandingHeroDemo));
          expect(
            Theme.of(hero).brightness,
            dark ? Brightness.dark : Brightness.light,
          );
          final glass = landingGlass(hero);
          if (contrast) {
            expect(glass.gradient, isNull);
            expect(glass.boxShadow, isEmpty);
            expect(find.byType(ShaderMask), findsNothing);
          } else {
            expect(glass.gradient, isNotNull);
            expect(find.byType(ShaderMask), findsOneWidget);
          }
          expect(state.themeMode, dark ? ThemeMode.dark : ThemeMode.light);
          final target = find.byKey(const ValueKey('landing-search'));
          await tester.ensureVisible(target);
          await settleLanding(tester);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          auth.dispose();
          state.dispose();
        },
      );
    }
  }

  testWidgets(
    'hero does not present a greeting as the result of an unmatched query',
    (tester) async {
      await tester.pumpWidget(
        Provider<AdminWorkspaceService>(
          create: (_) => DemoDictionaryService(),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LandingHeroDemo(
                  words: const [
                    {'word': 'xin chào'},
                  ],
                  loading: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('demo-mode-speech')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('hero-text-input')),
        'không có mẫu 123',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa có mẫu khớp với nội dung vừa nhập.'),
        findsOneWidget,
      );
      expect(find.byType(PublicSignPreview), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'public lookup, media preview, FAQ and motion control work without a guest session',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dictionary = LandingDictionaryService();
      final auth = AuthProvider(authService: FakeAuthService());
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/home',
          auth: auth,
          state: state,
          adminService: dictionary,
          learningService: LandingLearningService(),
        ),
      );
      await settleLanding(tester);
      expect(find.text('97'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      final search = find.byKey(const ValueKey('landing-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'cảm ơn');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleLanding(tester);
      expect(dictionary.calls, ['', 'chào', 'cảm ơn']);
      await tester.ensureVisible(find.text('cảm ơn').last);
      await tester.tap(find.text('cảm ơn').last);
      await settleLanding(tester);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await settleLanding(tester);
      final faq = find.text('Tôi có cần tài khoản để xem từ điển?');
      await tester.ensureVisible(faq);
      await tester.tap(faq);
      await settleLanding(tester);
      expect(find.textContaining('Không. Từ điển'), findsOneWidget);
      await tester.tap(find.byTooltip('Bật chuyển động'));
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.byTooltip('Giảm chuyển động'), findsOneWidget);
      await settleLanding(tester);
      await tester.tap(find.text('SignVoice').first);
      await settleLanding(tester);
      final landingScroll = tester.widget<SingleChildScrollView>(
        find
            .descendant(
              of: find.byType(WebLandingPage),
              matching: find.byType(SingleChildScrollView),
            )
            .first,
      );
      expect(landingScroll.controller!.offset, 0);
      expect(auth.isAuthenticated, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );

  for (final size in [
    const Size(1440, 900),
    const Size(1024, 900),
    const Size(768, 1024),
    const Size(375, 812),
  ]) {
    testWidgets('large text and reduced motion show final content at $size', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthProvider(authService: FakeAuthService()),
          state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/home',
          auth: auth,
          state: state,
          adminService: LandingDictionaryService(),
          learningService: LandingLearningService(),
        ),
      );
      await settleLanding(tester);
      expect(find.byType(WebLandingPage), findsOneWidget);
      final search = find.byKey(const ValueKey('landing-search'));
      await tester.ensureVisible(search);
      await settleLanding(tester);
      for (final reveal in find.byType(LandingReveal).evaluate()) {
        expect(MediaQuery.disableAnimationsOf(reveal), true);
        final fade = tester.widget<FadeTransition>(
          find
              .descendant(
                of: find.byWidget(reveal.widget),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(fade.opacity.value, 1);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    });
  }

  testWidgets(
    'public API failure stays honest and a later search can recover',
    (tester) async {
      final dictionary = LandingDictionaryService()..fail = true;
      final auth = AuthProvider(authService: FakeAuthService());
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/home',
          auth: auth,
          state: state,
          adminService: dictionary,
          learningService: LandingLearningService(),
        ),
      );
      await settleLanding(tester);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('97'), findsNothing);
      final search = find.byKey(const ValueKey('landing-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'chào');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleLanding(tester);
      expect(find.text('Chưa thể tra cứu. Bạn hãy thử lại.'), findsOneWidget);
      dictionary.fail = false;
      await tester.ensureVisible(search);
      await tester.tap(search);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleLanding(tester);
      expect(find.text('Chưa thể tra cứu. Bạn hãy thử lại.'), findsNothing);
      expect(auth.isAuthenticated, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );

  test('public and authenticated locations remain distinct', () {
    expect(webLocation('S01'), '/home');
    expect(webLocation('S05'), '/login');
    expect(webLocation('S08'), '/dashboard');
  });
  testWidgets(
    'default Web opens landing, login and public dictionary are reachable',
    (tester) async {
      final auth = AuthProvider(authService: FakeAuthService());
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          auth: auth,
          state: state,
          adminService: DemoDictionaryService(),
          learningService: LandingLearningService(),
        ),
      );
      await settleLanding(tester);
      expect(find.byType(WebLandingPage), findsOneWidget);
      await tester.tap(find.text('Đăng nhập').first);
      await settleLanding(tester);
      expect(find.byType(AuthScreen), findsOneWidget);
      openRoot(tester.element(find.byType(AuthScreen)), 'S22');
      await settleLanding(tester);
      expect(find.byType(DictionaryScreen), findsOneWidget);
      expect(auth.isAuthenticated, false);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );
  for (final size in [
    const Size(1440, 900),
    const Size(1024, 900),
    const Size(768, 1024),
    const Size(375, 812),
  ]) {
    testWidgets('WebLandingPage renders and switches public preview at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = AuthProvider(authService: FakeAuthService());
      final state = AppState();
      addTearDown(auth.dispose);
      addTearDown(state.dispose);

      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/home',
          auth: auth,
          state: state,
          adminService: DemoDictionaryService(),
          learningService: LandingLearningService(),
        ),
      );
      await settleLanding(tester);

      expect(find.byType(WebLandingPage), findsOneWidget);
      expect(
        find.text(
          'Kết nối giao tiếp,\nxóa nhòa khoảng cách.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.byType(LandingHeroDemo), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('demo-sample-0')));
      await tester.tap(find.byKey(const ValueKey('demo-sample-0')));
      await settleLanding(tester);
      expect(find.byKey(const ValueKey('demo-sample-0')), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('demo-mode-speech')),
      );
      await tester.tap(find.byKey(const ValueKey('demo-mode-speech')));
      await settleLanding(tester);
      expect(find.text('Ký hiệu tương ứng'), findsOneWidget);

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('WebLandingPage navigates to register and starts guest trial', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = AuthProvider(authService: FakeAuthService());
    final state = AppState();
    addTearDown(auth.dispose);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      SignVoiceApp(
        webRouting: true,
        initialScreen: '/welcome',
        auth: auth,
        state: state,
        adminService: DemoDictionaryService(),
        learningService: LandingLearningService(),
      ),
    );
    await settleLanding(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('landing-guest-cta')));
    await tester.tap(find.byKey(const ValueKey('landing-guest-cta')));
    await settleLanding(tester);
    expect(find.text('Dùng thử SignVoice trong 10 phút'), findsOneWidget);

    await tester.tap(find.text('Để sau'));
    await settleLanding(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('landing-primary-cta')),
    );
    await tester.tap(find.byKey(const ValueKey('landing-primary-cta')));
    await settleLanding(tester);
    expect(find.text('Tạo tài khoản'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
