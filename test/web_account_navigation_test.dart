import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/features/home/web_dashboard.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/widgets/user_avatar.dart';
import 'package:sign_voice/widgets/web_account_menu.dart';
import 'package:sign_voice/widgets/web_workspace.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import 'auth_fixtures.dart';
import 'user_data_integration_test.dart' show UserDataFixture;

class PendingDashboardService extends DemoLearningService {
  final pending = Completer<LearningRecord>();
  @override
  Future<LearningRecord> insights({int days = 7, int page = 1}) =>
      pending.future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'guest account menu exposes preferences without profile or schedule',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthProvider(
        authService: FakeAuthService(restoredUser: testUser(guest: true)),
      );
      await auth.initialize();
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: 'S28',
          auth: auth,
          state: state,
          learningService: DemoLearningService(),
          adminService: DemoDictionaryService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menu tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ'), findsNothing);
      expect(find.text('Lịch học'), findsNothing);
      expect(find.text('Cài đặt giọng nói'), findsOneWidget);
      await tester.tap(find.text('Cài đặt giọng nói'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tốc độ đọc'), findsOneWidget);
      expect(find.text('Cần tài khoản cá nhân'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );
  test('detail and account destinations keep semantic selection', () {
    expect(
      webDestinationSelected(Uri.parse('/conversations/abc'), '/history'),
      isTrue,
    );
    expect(
      webDestinationSelected(Uri.parse('/study-reminder'), '/profile'),
      isTrue,
    );
    expect(
      webDestinationSelected(Uri.parse('/notifications'), '/profile'),
      isTrue,
    );
  });
  testWidgets(
    'bulk delete is disabled for filters and confirms the full count',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = UserDataFixture();
      fixture.conversations.addAll([
        for (var i = 0; i < 2; i++)
          {
            '_id': 'item$i',
            'content': 'Hội thoại $i',
            'direction': 'TEXT',
            'favorite': i == 0,
            'createdAt': '2026-10-30T00:00:00Z',
          },
      ]);
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
      await tester.enterText(find.byType(TextField).first, 'Hội thoại');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quản lý hội thoại'));
      await tester.pumpAndSettle();
      final clear = find.byWidgetPredicate(
        (w) => w is PopupMenuItem<String> && w.value == 'clear',
      );
      expect(tester.widget<PopupMenuItem<String>>(clear).enabled, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      state.update(() {
        state.historyTotal = 42;
        state.historyPages = 3;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Quản lý hội thoại'));
      await tester.pumpAndSettle();
      expect(tester.widget<PopupMenuItem<String>>(clear).enabled, isTrue);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(find.text('Xóa toàn bộ 42 hội thoại?'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(state.history.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      auth.dispose();
      fixture.api.dispose();
    },
  );
  testWidgets('header avatar follows account state and menu opens profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState();
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
    state.update(() {
      state.name = 'Ảnh mới';
      state.avatarUrl = 'https://avatar.example.invalid/new.png';
      state.avatarColor = 2;
    });
    await tester.pumpAndSettle();
    final header = find.descendant(
      of: find.byWidgetPredicate((w) => w is WebAccountMenu && !w.sidebar),
      matching: find.byType(UserAvatar),
    );
    expect(tester.widget<UserAvatar>(header).url, state.avatarUrl);
    expect(tester.widget<UserAvatar>(header).color, avatarColors[2]);
    await tester.tap(find.byTooltip('Menu tài khoản'));
    await tester.pumpAndSettle();
    expect(find.text('Lịch học'), findsOneWidget);
    await tester.tap(find.text('Hồ sơ'));
    await tester.pumpAndSettle();
    expect(find.byType(WebAccountMenu), findsNWidgets(2));
    expect(find.text('Cá nhân'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    auth.dispose();
  });
  testWidgets(
    'dashboard reserves loading cards and exposes errors near the greeting',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      final state = AppState();
      final service = PendingDashboardService();
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
            child: const MaterialApp(home: WebDashboard()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Đang tải mục tiêu và hoạt động',
        ),
        findsOneWidget,
      );
      service.pending.completeError(StateError('fixture failed'));
      await tester.pumpAndSettle();
      final error = find.text('Chưa cập nhật được tiến độ. Hãy thử lại.');
      expect(error, findsOneWidget);
      expect(tester.getTopLeft(error).dy, lessThan(400));
      expect(find.text('Từ mới hôm nay'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      auth.dispose();
    },
  );
}
