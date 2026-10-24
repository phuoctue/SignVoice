import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/core/navigation.dart';
import 'package:sign_voice/features/home/home_screen.dart';
import 'package:sign_voice/features/learning/learning_widgets.dart';
import 'package:sign_voice/providers/auth_provider.dart';

import 'auth_fixtures.dart';

void main() {
  test('lưu và xóa đúng hội thoại được chọn', () {
    final state = AppState();
    state.saveConversation(
      'Một hội thoại mới',
      ConversationDirection.speechToText,
    );
    final added = state.selectedConversation!;
    expect(added.content, 'Một hội thoại mới');
    state.selectConversation(state.history.last);
    expect(state.selectedConversation!.id, isNot(added.id));
    state.removeConversation(added.id);
    expect(state.history.any((h) => h.id == added.id), isFalse);
    state.dispose();
  });

  test('yêu thích được bật/tắt và xóa dữ liệu demo có hiệu lực', () {
    final state = AppState();
    state.toggleSign('Giúp đỡ');
    expect(state.favorites, contains('Giúp đỡ'));
    state.toggleSign('Giúp đỡ');
    expect(state.favorites, isNot(contains('Giúp đỡ')));
    state.addWord('Xin chào');
    state.clearLocalData();
    expect(state.history, isEmpty);
    expect(state.favorites, isEmpty);
    expect(state.sentence, isEmpty);
    state.dispose();
  });

  for (final id in screenNames.keys) {
    testWidgets('$id dựng được ở kích thước điện thoại', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        SignVoiceApp(
          initialScreen: id,
          auth: auth,
          adminService: DemoDictionaryService(),
          learningService: DemoLearningService(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      // Dọn timer và animation trước khi kết thúc từng test.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('form đăng nhập chặn email sai và mật khẩu ngắn', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthProvider(authService: FakeAuthService());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        initialScreen: 'S05',
        auth: auth,
        adminService: DemoDictionaryService(),
        learningService: DemoLearningService(),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'sai-email');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    final login = find.widgetWithText(FilledButton, 'Đăng nhập');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pump();
    expect(find.text('Email không đúng định dạng.'), findsOneWidget);
    expect(find.text('Mật khẩu cần ít nhất 8 ký tự.'), findsOneWidget);
  });

  testWidgets('dùng thử mở trang chủ và điều hướng từ điển', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthProvider(authService: FakeAuthService());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        initialScreen: 'S05',
        auth: auth,
        adminService: DemoDictionaryService(),
        learningService: DemoLearningService(),
      ),
    );
    final guest = find.text('Dùng thử không cần tài khoản');
    await tester.ensureVisible(guest);
    await tester.tap(guest);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('Từ điển'));
    await tester.pumpAndSettle();
    expect(find.text('Từ điển ký hiệu'), findsOneWidget);
    expect(find.text('Khám phá'), findsOneWidget);
    expect(find.text('Chào hỏi'), findsOneWidget);
  });

  testWidgets('mở đúng mục từ điển được chọn', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        initialScreen: 'S22',
        auth: auth,
        adminService: DemoDictionaryService(),
        learningService: DemoLearningService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chào hỏi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cảm ơn'));
    await tester.pumpAndSettle();
    expect(find.byType(LearningWordContent), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LearningWordContent),
        matching: find.text('Bày tỏ sự biết ơn.'),
      ),
      findsOneWidget,
    );
  });
}
