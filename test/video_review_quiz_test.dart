import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/features/learning/video_review_quiz_screen.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/widgets/ui.dart';

class VideoQuizService extends LearningService {
  List<String> stored = ['', ''];
  int writes = 0, submits = 0;
  bool failSave = false, failSubmit = false, failLoad = false;
  bool finished = false;
  Completer<void>? saveGate;
  Completer<LearningRecord>? adviceGate;
  final choices = [
    'Xin chào',
    'Bàn bạc',
    'Gia đình và những người thân trong cuộc sống',
    'Ôn tập',
  ];

  LearningRecord snapshot(String id) => {
    '_id': id,
    'topicId': 'topic',
    'kind': 'VIDEO_CHOICE',
    'status': finished ? 'COMPLETED' : 'DRAFT',
    'answers': [...stored],
    'questions': List.generate(
      2,
      (i) => {
        'entryId': 'word-$i',
        'videoUrl': '',
        'imageUrls': <String>[],
        'options': List.generate(
          4,
          (j) => {'value': '$i-$j', 'label': choices[j]},
        ),
      },
    ),
    if (finished)
      'result': {
        'source': 'video-choice',
        'score': 5,
        'total': 2,
        'items': List.generate(
          2,
          (i) => {
            'entryId': 'word-$i',
            'word': choices[i],
            'correctAnswer': choices[i],
            'selectedAnswer': choices[int.parse(stored[i].split('-').last)],
            'score': i == 0 ? 10 : 0,
            'applied': true,
            'definition': 'Nội dung tham khảo đã lưu.',
          },
        ),
      },
  };
  @override
  Future<LearningRecord> quiz(String id) async {
    if (failLoad) throw ApiException(message: 'Mạng bị gián đoạn');
    return LearningRecord.from(jsonDecode(jsonEncode(snapshot(id))) as Map);
  }

  @override
  Future<LearningRecord> saveQuizAnswers(
    String id,
    List<String> answers,
  ) async {
    writes++;
    await saveGate?.future;
    if (failSave) throw ApiException(message: 'Chưa lưu được lựa chọn');
    stored = [...answers];
    return snapshot(id);
  }

  @override
  Future<LearningRecord> submitQuiz(String id) async {
    submits++;
    if (failSubmit) throw ApiException(message: 'Chưa nộp được bài');
    finished = true;
    return snapshot(id);
  }

  @override
  Future<LearningRecord> quizAdvice(String id) =>
      adviceGate?.future ??
      Future.value({
        'source': 'rules',
        'advice': 'Xem lại video từ trả lời sai.',
      });
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    VideoQuizService service, {
    double width = 390,
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Provider<LearningService>.value(
        value: service,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const ReviewQuizScreen(quizId: 'quiz'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).first);
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AppButton, 'Câu tiếp'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmSubmit(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AppButton, 'Nộp bài'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Nộp bài').last);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await choose(tester, 'Xin chào');
    await next(tester);
    await choose(tester, 'Ôn tập');
    await confirmSubmit(tester);
  }

  testWidgets(
    'video quiz has four tappable choices, no camera and disabled next until a selection',
    (tester) async {
      final service = VideoQuizService();
      await mount(tester, service);
      expect(find.text('Mở camera nhận diện'), findsNothing);
      expect(find.text('Ký hiệu này có nghĩa là gì?'), findsOneWidget);
      final nextButton = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Câu tiếp'),
      );
      expect(nextButton.onPressed, isNull);
      for (final label in service.choices) {
        expect(find.text(label), findsOneWidget);
      }
      await choose(tester, 'Bàn bạc');
      await next(tester);
      expect(service.stored, ['0-1', '']);
      expect(find.text('Câu 2 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Câu trước'));
      await tester.pumpAndSettle();
      expect(find.text('Câu 1 / 2'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    },
  );

  testWidgets(
    'restores persisted choices and opens the first unanswered question',
    (tester) async {
      final service = VideoQuizService()..stored = ['0-2', ''];
      await mount(tester, service);
      expect(find.text('Câu 2 / 2'), findsOneWidget);
      expect(find.text('Đã chọn 1/2'), findsOneWidget);
      await tester.tap(find.byTooltip('Câu trước'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(service.writes, 0);
    },
  );

  testWidgets(
    'a failed save keeps the selected answer and retries without losing the question',
    (tester) async {
      final service = VideoQuizService()..failSave = true;
      await mount(tester, service);
      await choose(tester, 'Bàn bạc');
      await next(tester);
      expect(find.text('Câu 1 / 2'), findsOneWidget);
      expect(find.text('Chưa lưu được lựa chọn'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(service.stored, ['', '']);
      service.failSave = false;
      await next(tester);
      expect(service.stored, ['0-1', '']);
      expect(find.text('Câu 2 / 2'), findsOneWidget);
    },
  );

  testWidgets('pending save disables duplicate next taps', (tester) async {
    final service = VideoQuizService()..saveGate = Completer<void>();
    await mount(tester, service);
    await choose(tester, 'Xin chào');
    await tester.tap(find.widgetWithText(AppButton, 'Câu tiếp'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.writes, 1);
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, 'Câu tiếp')).busy,
      isTrue,
    );
    service.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Câu 2 / 2'), findsOneWidget);
  });

  testWidgets(
    'failed submission retains all saved answers and successful retry displays deterministic results',
    (tester) async {
      final service = VideoQuizService()..failSubmit = true;
      await mount(tester, service);
      await finish(tester);
      expect(find.text('Chưa nộp được bài'), findsOneWidget);
      expect(service.stored, ['0-0', '1-3']);
      service.failSubmit = false;
      await confirmSubmit(tester);
      expect(find.text('5 / 10 điểm'), findsOneWidget);
      expect(find.text('Đúng 1/2 câu'), findsOneWidget);
      expect(find.text('Đáp án: Bàn bạc'), findsOneWidget);
      expect(service.submits, 2);
    },
  );

  testWidgets('AI feedback never blocks saved results or navigation', (
    tester,
  ) async {
    final service = VideoQuizService()
      ..adviceGate = Completer<LearningRecord>();
    await mount(tester, service);
    await finish(tester);
    final button = find.widgetWithText(AppButton, 'Nhận gợi ý ôn tập');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(find.text('5 / 10 điểm'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Về chủ đề'), findsOneWidget);
    service.adviceGate!.complete({
      'source': 'lm-studio',
      'advice': 'Hãy ôn lại từ bàn bạc trong 5 phút.',
    });
    await tester.pumpAndSettle();
    expect(find.text('Gợi ý từ LM Studio'), findsOneWidget);
    expect(find.text('Hãy ôn lại từ bàn bạc trong 5 phút.'), findsOneWidget);
  });

  testWidgets('quiz load error has an inline retry', (tester) async {
    final service = VideoQuizService()..failLoad = true;
    await mount(tester, service);
    expect(find.text('Mạng bị gián đoạn'), findsOneWidget);
    service.failLoad = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Câu 1 / 2'), findsOneWidget);
  });

  testWidgets(
    'back action offers to save the current selection before leaving',
    (tester) async {
      final service = VideoQuizService();
      await tester.pumpWidget(
        Provider<LearningService>.value(
          value: service,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ReviewQuizScreen(quizId: 'quiz'),
                    ),
                  ),
                  child: const Text('Mở quiz'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở quiz'));
      await tester.pumpAndSettle();
      await choose(tester, 'Bàn bạc');
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.text('Lưu lựa chọn trước khi thoát?'), findsOneWidget);
      await tester.tap(find.text('Lưu & thoát'));
      await tester.pumpAndSettle();
      expect(service.stored, ['0-1', '']);
      expect(find.text('Mở quiz'), findsOneWidget);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'narrow phone, large text and $brightness theme keep choices and footer usable',
      (tester) async {
        final service = VideoQuizService();
        await mount(
          tester,
          service,
          width: 320,
          scale: 2,
          brightness: brightness,
        );
        for (final label in service.choices) {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(
          tester.getRect(find.widgetWithText(AppButton, 'Câu tiếp')).bottom,
          lessThanOrEqualTo(844),
        );
        await finish(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('5 / 10 điểm'), findsOneWidget);
      },
    );
  }
}
