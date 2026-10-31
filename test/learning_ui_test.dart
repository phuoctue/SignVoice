import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/widgets/ui.dart';
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

class ControlledRateService extends DemoLearningService {
  final acknowledgment = Completer<void>();
  final reconciliation = Completer<LearningPage>();
  int reads = 0;
  @override
  Future<LearningPage> topic(String id, {int page = 1, String stage = 'ALL'}) {
    if (reads++ > 0) return reconciliation.future;
    return super.topic(id, page: page, stage: stage);
  }

  @override
  Future<void> rate(String id, String stage) async {
    await acknowledgment.future;
    await super.rate(id, stage);
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

  testWidgets(
    'saved feedback waits for the write but never waits for a second page read',
    (tester) async {
      final service = ControlledRateService()..enrolled = true;
      await mount(
        tester,
        service,
        screen: '/learn/topic/${DemoLearningService.topicId}?study=1',
      );
      final firstWord = service.words.first;
      final button = find.byKey(
        ValueKey("learn-rate-${firstWord['_id']}-REMEMBERED"),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Đã lưu: Đã nhớ'), findsNothing);
      expect(service.ratings, isEmpty);
      service.acknowledgment.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Đã lưu: Đã nhớ'), findsOneWidget);
      expect(find.byType(TopicLearningScreen), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
        find.byKey(ValueKey("learning-word-${firstWord['_id']}")),
        findsNothing,
      );
      expect(service.reconciliation.isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      service.reconciliation.complete(LearningPage(items: []));
      await tester.pump();
    },
  );

  testWidgets('dictionary has three sections and opens the chosen topic', (
    tester,
  ) async {
    final service = DemoLearningService();
    await mount(tester, service);
    expect(find.text('Khám phá'), findsOneWidget);
    expect(find.text('Đang học'), findsOneWidget);
    expect(find.text('Bộ sưu tập'), findsOneWidget);
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
      final rating = find.byKey(
        ValueKey("learn-rate-${service.words.first['_id']}-REMEMBERED"),
      );
      await tester.ensureVisible(rating);
      await tester.pumpAndSettle();
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
  testWidgets('continue learning excludes remembered and review words', (
    tester,
  ) async {
    final service = DemoLearningService()..enrolled = true;
    final remembered = service.words[0];
    final review = service.words[1];
    service.ratings['${remembered['_id']}'] = 'REMEMBERED';
    service.ratings['${review['_id']}'] = 'REVIEW';
    await mount(
      tester,
      service,
      screen: '/learn/topic/${DemoLearningService.topicId}?study=1',
    );
    expect(find.text('${remembered['word']}'), findsNothing);
    expect(find.text('${review['word']}'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Đã nhớ'), findsWidgets);
    final button = find.widgetWithText(AppButton, 'Đã nhớ').first;
    final nextWord = service.words[2]['word'];
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('$nextWord'), findsNothing);
    expect(service.ratings.values.where((v) => v == 'REMEMBERED').length, 2);
  });

  testWidgets('remembered list is read only and review opens a quiz', (
    tester,
  ) async {
    final service = DemoLearningService()..enrolled = true;
    final remembered = service.words[0];
    final review = service.words[1];
    service.ratings['${remembered['_id']}'] = 'REMEMBERED';
    service.ratings['${review['_id']}'] = 'REVIEW';
    await mount(
      tester,
      service,
      screen: '/learn/topic/${DemoLearningService.topicId}?study=1',
    );
    final rememberedFilter = find.widgetWithText(ChoiceChip, 'Đã nhớ');
    await tester.ensureVisible(rememberedFilter);
    await tester.tap(rememberedFilter);
    await tester.pumpAndSettle();
    expect(find.text('${remembered['word']}'), findsOneWidget);
    expect(find.text('${review['word']}'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Đã nhớ'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Ôn tập'), findsNothing);
    final reviewFilter = find.widgetWithText(ChoiceChip, 'Ôn tập');
    await tester.ensureVisible(reviewFilter);
    await tester.tap(reviewFilter);
    await tester.pumpAndSettle();
    expect(find.text('${review['word']}'), findsOneWidget);
    expect(find.text('${remembered['word']}'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Đã nhớ'), findsNothing);
    expect(
      find.widgetWithText(AppButton, 'Bắt đầu quiz ôn tập'),
      findsOneWidget,
    );
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
    expect(
      next,
      findsNothing,
    ); // Offscreen cards and controls are built lazily.
    await tester.scrollUntilVisible(
      next,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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
