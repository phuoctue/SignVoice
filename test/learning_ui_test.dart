import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/widgets/ui.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/features/learning/review_quiz_screen.dart';
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

class QuizLearningService extends DemoLearningService {
  bool offline = false;
  int submissions = 0;
  final draft = <String, dynamic>{
    '_id': '000000000000000000000099',
    'topicId': DemoLearningService.topicId,
    'status': 'DRAFT',
    'questions': [
      {
        'entryId': '000000000000000000000010',
        'word': 'Xin chào',
        'prompt': 'Viết câu ví dụ sử dụng từ Xin chào.',
        'answer': '',
      },
    ],
  };
  @override
  Future<LearningRecord> startQuiz(String topicId) async => draft;
  @override
  Future<LearningRecord> quiz(String id) async => draft;
  @override
  Future<LearningRecord> saveQuizAnswers(
    String id,
    List<String> answers,
  ) async {
    (draft['questions'] as List)[0]['answer'] = answers[0];
    return draft;
  }

  @override
  Future<LearningRecord> submitQuiz(String id) async {
    submissions++;
    if (offline) {
      throw ServerException(
        message: 'LM Studio chưa chấm được bài. Câu trả lời đã lưu.',
      );
    }
    draft['status'] = 'COMPLETED';
    draft['result'] = {
      'source': 'lm-studio',
      'score': 9,
      'feedback': 'Bạn sử dụng từ đúng ngữ cảnh.',
      'items': [
        {
          'word': 'Xin chào',
          'score': 9,
          'feedback': 'Câu rõ nghĩa.',
          'answer': (draft['questions'] as List)[0]['answer'],
          'stage': 'REMEMBERED',
          'applied': true,
        },
      ],
    };
    return draft;
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

  testWidgets(
    'quiz opens from review, requires an answer and shows AI results',
    (tester) async {
      final service = QuizLearningService()..enrolled = true;
      service.ratings['000000000000000000000010'] = 'REVIEW';
      await mount(
        tester,
        service,
        screen: '/learn/topic/${DemoLearningService.topicId}?study=1',
      );
      final filter = find.widgetWithText(ChoiceChip, 'Ôn tập');
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      final start = find.widgetWithText(AppButton, 'Bắt đầu quiz ôn tập');
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(find.byType(ReviewQuizScreen), findsOneWidget);
      final submit = find.widgetWithText(AppButton, 'Nộp bài & AI đánh giá');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(service.submissions, 0);
      expect(
        find.text('Hãy trả lời câu hỏi trước khi tiếp tục.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Xin chào các bạn.');
      final retry = find.widgetWithText(AppButton, 'Lưu & chấm lại bằng AI');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Kết quả ôn tập'), findsOneWidget);
      expect(find.text('Đánh giá bởi LM Studio'), findsOneWidget);
      expect(find.text('9 / 10 điểm'), findsOneWidget);
    },
  );

  testWidgets(
    'offline AI keeps answers and allows retry without a fake score',
    (tester) async {
      final service = QuizLearningService()..offline = true;
      await mount(
        tester,
        service,
        screen: '/learn/quiz/000000000000000000000099',
      );
      await tester.enterText(find.byType(TextField), 'Xin chào các bạn.');
      final submit = find.widgetWithText(AppButton, 'Nộp bài & AI đánh giá');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Kết quả ôn tập'), findsNothing);
      expect(
        (service.draft['questions'] as List)[0]['answer'],
        'Xin chào các bạn.',
      );
      service.offline = false;
      final retry = find.widgetWithText(AppButton, 'Lưu & chấm lại bằng AI');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Kết quả ôn tập'), findsOneWidget);
      expect(service.submissions, 2);
    },
  );

  testWidgets('quiz draft restores saved answer after reopening its route', (
    tester,
  ) async {
    final service = QuizLearningService();
    (service.draft['questions'] as List)[0]['answer'] = 'Câu đã lưu.';
    await mount(
      tester,
      service,
      screen: '/learn/quiz/000000000000000000000099',
    );
    expect(find.text('Câu đã lưu.'), findsOneWidget);
    expect(service.submissions, 0);
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
