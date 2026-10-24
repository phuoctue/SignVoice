import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/learning/learning_hub.dart';
import 'package:sign_voice/features/learning/topic_learning_screen.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import 'auth_fixtures.dart';

class PagedLearningService extends DemoLearningService {
  final List<int> requestedPages = [];
  @override
  Future<LearningPage> topics({int page = 1, String search = ''}) async {
    requestedPages.add(page);
    final topics = List.generate(
      12,
      (i) => <String, dynamic>{
        '_id': '$i'.padLeft(24, '0'),
        'name': 'Chủ đề văn hóa, tín ngưỡng và giao tiếp thường ngày số $i',
        'wordCount': 13,
        'learnerCount': 0,
      },
    );
    return LearningPage(
      items: topics.skip((page - 1) * 10).take(10).toList(),
      page: page,
      pages: 2,
      total: 12,
    );
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    DemoLearningService service, {
    String screen = 'S22',
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        initialScreen: screen,
        learningService: service,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dictionary has three sections and opens the chosen topic', (
    tester,
  ) async {
    final service = DemoLearningService();
    await mount(tester, service);
    expect(find.text('Khám phá'), findsOneWidget);
    expect(find.text('Đang học'), findsOneWidget);
    expect(find.text('Từ của tôi'), findsOneWidget);
    await tester.tap(find.text('Chào hỏi'));
    await tester.pumpAndSettle();
    expect(find.byType(TopicLearningScreen), findsOneWidget);
    expect(find.text('Bắt đầu học'), findsOneWidget);
    expect(service.enrolled, isFalse);
  });
  testWidgets(
    'starting and self rating stores progress then shows it in studying',
    (tester) async {
      final service = DemoLearningService();
      await mount(tester, service);
      await tester.tap(find.text('Chào hỏi'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Bắt đầu học'));
      await tester.tap(find.text('Bắt đầu học'));
      await tester.pumpAndSettle();
      expect(service.enrolled, isTrue);
      // Ratings are explicit buttons; looking at a card alone must not mark it remembered.
      expect(service.ratings, isEmpty);
      final rating = find.text('Đã nhớ').last;
      await tester.ensureVisible(rating);
      await tester.tap(rating);
      await tester.pumpAndSettle();
      expect(service.ratings.values, contains('REMEMBERED'));
      await tester.pumpWidget(const SizedBox.shrink());
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          initialScreen: '/learn?tab=1',
          learningService: service,
          state: AppState(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đã nhớ 1 / 10 từ'), findsOneWidget);
    },
  );
  testWidgets('my words can be created with meaning and example', (
    tester,
  ) async {
    final service = DemoLearningService();
    await mount(tester, service, screen: '/learn?tab=2');
    await tester.tap(find.text('Tạo từ mới'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Chúc ngủ ngon');
    await tester.enterText(fields.at(1), 'Lời chúc trước khi đi ngủ.');
    await tester.enterText(fields.at(2), 'Chúc bạn ngủ ngon.');
    await tester.ensureVisible(find.text('Lưu từ'));
    await tester.tap(find.text('Lưu từ'));
    await tester.pumpAndSettle();
    expect(service.personal.single['word'], 'Chúc ngủ ngon');
    expect(service.personal.single['usageExample'], 'Chúc bạn ngủ ngon.');
    expect(find.text('Chúc ngủ ngon'), findsOneWidget);
  });
  testWidgets('large text and a long topic name do not overflow', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState()
      ..bindAccount(auth.user!.id, asGuest: false)
      ..fontScale = 1.4;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        initialScreen: 'S22',
        learningService: PagedLearningService(),
        state: state,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LearningHub), findsOneWidget);

  });

  testWidgets('topic pagination requests the next ten results', (tester) async {
    final service = PagedLearningService();
    await mount(tester, service);
    final next = find.byTooltip('Trang sau');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(service.requestedPages, [1, 2]);
    expect(find.text('Trang 2 / 2'), findsOneWidget);
    expect(
      find.text('Chủ đề văn hóa, tín ngưỡng và giao tiếp thường ngày số 10'),
      findsOneWidget,
    );
  });
}
