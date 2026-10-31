import 'package:flutter/material.dart';

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/core/navigation.dart';
import 'package:sign_voice/core/theme.dart';
import 'package:sign_voice/features/home/web_dashboard.dart';
import 'package:sign_voice/widgets/web_workspace.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';

import 'auth_fixtures.dart';
import 'recall_review_quiz_test.dart' show RecallQuizService;

class DashboardService extends DemoLearningService {
  int requests = 0;
  @override
  Future<LearningRecord> insights({int days = 7, int page = 1}) async {
    requests++;
    return {
      'today': {'newWords': 3, 'reviewed': 6},
      'goals': {'newWords': 5, 'reviewWords': 10},
      'activity': [
        {'date': '2026-10-29', 'newWords': 3, 'reviewed': 6},
      ],
    };
  }

  @override
  Future<LearningPage> progress({int page = 1, String stage = 'ALL'}) async {
    requests++;
    return LearningPage(items: [], summary: {'remembered': 17, 'review': 9});
  }
}

void main() {
  const capture = bool.fromEnvironment('CAPTURE_DASHBOARD');
  setUpAll(() async {
    if (capture) {
      final font = FontLoader('DashboardPreview');
      font.addFont(
        File('C:/Windows/Fonts/segoeui.ttf')
            .readAsBytes()
            .then((value) => ByteData.sublistView(value)),
      );
      await font.load();
    }
  });
  testWidgets('Web route changes ask before leaving unfinished quiz', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        webRouting: true,
        initialScreen: '/learn/quiz/q1',
        state: AppState(),
        auth: auth,
        learningService: RecallQuizService(),
        adminService: DemoDictionaryService(),
      ),
    );
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(find.text('Ôn ký hiệu').first));
    router.go('/profile');
    await tester.pumpAndSettle();
    expect(find.text('Rời bài ôn tập?'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục ôn'));
    await tester.pumpAndSettle();
    expect(find.text('Ôn ký hiệu'), findsOneWidget);
    router.go('/profile');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu & thoát'));
    await tester.pumpAndSettle();
    expect(find.text('Ôn ký hiệu'), findsNothing);
    expect(router.routeInformationProvider.value.uri.path, '/profile');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('web aliases preserve filters and identifiers', () {
    for (final entry in webPaths.entries) {
      expect(legacyLocation(webLocation(entry.key)), entry.key);
    }
    expect(webLocation('S22?search=x'), '/dictionary?search=x');
    expect(legacyLocation('/S22'), 'S22');
  });
  for (final size in [
    const Size(1024, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('dashboard values and bounded requests $size dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = await authenticatedProvider();
        addTearDown(auth.dispose);
        final service = DashboardService();
        final state = AppState();
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: auth),
              Provider<LearningService>.value(value: service),
              Provider<AdminWorkspaceService>.value(
                value: DemoDictionaryService(),
              ),
            ],
            child: AppScope(
              state: state,
              child: MaterialApp(
                theme: makeTheme(dark: dark, highContrast: false).copyWith(
                  textTheme: capture
                      ? makeTheme(
                          dark: dark,
                          highContrast: false,
                        ).textTheme.apply(fontFamily: 'DashboardPreview')
                      : null,
                ),
                home: const WebDashboard(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('17'), findsOneWidget);
        expect(find.text('9'), findsOneWidget);
        expect(service.requests, 2);
        expect(tester.takeException(), isNull);
        if (capture && size.width == 1440) {
          await expectLater(
            find.byType(WebWorkspace),
            matchesGoldenFile(
              '../.runtime/dashboard-${dark ? 'dark' : 'light'}.png',
            ),
          );
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('Web router resolves alias, denies admin, returns push result', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        webRouting: true,
        initialScreen: 'S25',
        state: AppState(),
        auth: auth,
        learningService: DashboardService(),
        adminService: DemoDictionaryService(),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Cá nhân').first);
    final router = GoRouter.of(context);
    expect(router.routeInformationProvider.value.uri.path, '/profile');
    var returned = false;
    pushAppRoute(context, '/admin/users').then((_) => returned = true);
    await tester.pumpAndSettle();
    expect(find.text('Bạn không có quyền truy cập trang này.'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    router.go('/S22');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/dictionary');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
