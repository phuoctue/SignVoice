import 'package:flutter/material.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/widgets/web_workspace.dart';
import 'package:sign_voice/widgets/web_history_table.dart';

import 'auth_fixtures.dart';
import 'recall_review_quiz_test.dart' show RecallQuizService;
import 'user_data_integration_test.dart' show UserDataFixture;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('large-text desktop history retains access to later pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = UserDataFixture();
    fixture.settings['fontSize'] = 28;
    final state = AppState(service: fixture.service);
    final auth = await authenticatedProvider();
    await tester.pumpWidget(
      SignVoiceApp(
        webRouting: true,
        initialScreen: '/history',
        state: state,
        auth: auth,
        learningService: DemoLearningService(),
        adminService: DemoDictionaryService(),
      ),
    );
    await tester.pumpAndSettle();
    state.update(() => state.historyPages = 2);
    await tester.pumpAndSettle();
    expect(find.byType(WebHistoryTable), findsNothing);
    final more = find.text('Tải thêm hội thoại');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(state.historyPage, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    auth.dispose();
    fixture.api.dispose();
  });
  test(
    'sidebar selection ignores unrelated query and separates learning tabs',
    () {
      expect(
        webDestinationSelected(
          Uri.parse('/learn?search=abc&tab=2&page=3'),
          '/learn?tab=2',
        ),
        isTrue,
      );
      expect(
        webDestinationSelected(Uri.parse('/learn?tab=2&page=3'), '/learn'),
        isFalse,
      );
      expect(
        webDestinationSelected(
          Uri.parse('/collections/abcdef/add?search=x'),
          '/learn?tab=2',
        ),
        isTrue,
      );
      expect(
        webDestinationSelected(Uri.parse('/learn/insights?days=30'), '/learn'),
        isFalse,
      );
      expect(
        webDestinationSelected(
          Uri.parse('/dictionary/a?search=x'),
          '/dictionary',
        ),
        isTrue,
      );
    },
  );
  testWidgets(
    'sidebar uses an explicit toggle, resizes content and survives navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/history',
          state: AppState(),
          auth: auth,
          learningService: DemoLearningService(),
          adminService: DemoDictionaryService(),
        ),
      );
      await tester.pumpAndSettle();
      final shell = tester.state(find.byType(WebWorkspace));
      final sidebar = find.byKey(const ValueKey('web-sidebar'));
      final content = tester.getRect(find.byType(Scaffold).last);
      expect(tester.getSize(sidebar).width, 80);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 100));
      await mouse.moveTo(const Offset(40, 100));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 80);
      await tester.tap(find.byTooltip('Mở thanh điều hướng'));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 248);
      final expandedContent = tester.getRect(find.byType(Scaffold).last);
      expect(
        expandedContent.left,
        greaterThanOrEqualTo(tester.getRect(sidebar).right),
      );
      expect(expandedContent.right, content.right);
      expect(expandedContent.width, lessThan(content.width));
      expect(find.text('Cá nhân'), findsNothing);
      await mouse.moveTo(const Offset(500, 100));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 248);
      final router = GoRouter.of(tester.element(find.byType(WebWorkspace)));
      router.go('/dictionary');
      await tester.pumpAndSettle();
      expect(identical(shell, tester.state(find.byType(WebWorkspace))), isTrue);
      await tester.tap(find.byTooltip('Thu gọn thanh điều hướng'));
      await mouse.moveTo(const Offset(500, 100));
      await tester.pumpAndSettle();
      expect(tester.getSize(sidebar).width, 80);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'table exposes keyboard actions, favorite/delete and sortable columns',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opens = 0, favorites = 0, deletes = 0;
      final item = Conversation(
        id: 'a',
        content: 'Một hội thoại',
        createdAt: DateTime(2026, 10, 29),
        direction: ConversationDirection.text,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebHistoryTable(
                items: [item],
                onOpen: (_) => opens++,
                onFavorite: (_) => favorites++,
                onDelete: (_) => deletes++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Yêu thích'));
      await tester.pump();
      expect(favorites, 1);
      item.favorite = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebHistoryTable(
                items: [item],
                onOpen: (_) => opens++,
                onFavorite: (_) => favorites++,
                onDelete: (_) => deletes++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Bỏ yêu thích'), findsOneWidget);
      await tester.tap(find.byTooltip('Xóa hội thoại'));
      expect(deletes, 1);
      final openButton = find.byTooltip('Mở hội thoại');
      final button = tester.widget<IconButton>(
        find.ancestor(of: openButton, matching: find.byType(IconButton)),
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(openButton);
      expect(opens, 1);
      await tester.tap(find.text('Nội dung'));
      await tester.pump();
      expect(
        tester.widget<DataTable>(find.byType(DataTable)).sortColumnIndex,
        0,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(find.byType(PaginatedDataTable), findsNothing);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'query updates preserve quiz guard including same-shape destinations and browser route events',
    (tester) async {
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/learn/quiz/q1?entryId=a',
          state: AppState(),
          auth: auth,
          learningService: RecallQuizService(),
          adminService: DemoDictionaryService(),
        ),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.text('Ôn ký hiệu').first));
      router.go('/learn/quiz/q1?entryId=b');
      await tester.pumpAndSettle();
      expect(find.text('Rời bài ôn tập?'), findsNothing);
      router.go('/learn/topic/000000000000000000000001?study=1');
      await tester.pumpAndSettle();
      expect(find.text('Rời bài ôn tập?'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục ôn'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['entryId'],
        'b',
      );
      await router.routeInformationProvider.didPushRouteInformation(
        RouteInformation(uri: Uri.parse('/profile')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rời bài ôn tập?'), findsOneWidget);
      await tester.tap(find.text('Lưu & thoát'));
      await tester.pumpAndSettle();
      expect(find.text('Ôn ký hiệu'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'history route rebuilds favorite and deletion after acknowledged state changes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: 'S20',
          state: state,
          auth: auth,
          learningService: DemoLearningService(),
          adminService: DemoDictionaryService(),
        ),
      );
      await tester.pumpAndSettle();
      state.update(
        () => state.history.add(
          Conversation(
            id: 'one',
            content: 'Xin chào',
            createdAt: DateTime.now(),
            direction: ConversationDirection.text,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Yêu thích'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Bỏ yêu thích'), findsOneWidget);
      await tester.tap(find.byTooltip('Xóa hội thoại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa có hội thoại phù hợp'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
