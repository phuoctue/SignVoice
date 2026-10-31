import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/core/theme.dart';
import 'package:sign_voice/features/learning/recall_review_quiz_screen.dart';
import 'package:sign_voice/features/learning/quiz_practice_sheet.dart';
import 'package:sign_voice/features/learning/learning_widgets.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/widgets/ui.dart';

class RecallQuizService extends LearningService {
  List<String> stored = ['', ''];
  final words = ['xin chào', 'bàn bạc'];
  final responses = <int, LearningRecord>{}, hints = <int>{};
  int checks = 0, saves = 0, submits = 0, adviceCalls = 0;
  bool failCheck = false,
      failSave = false,
      failSubmit = false,
      failLoad = false,
      finished = false;
  String? matchOverride;
  Completer<void>? checkGate, saveGate;
  Completer<LearningRecord>? adviceGate;
  LearningRecord snapshot(String id) => {
    '_id': id,
    'topicId': 'topic',
    'kind': 'VIDEO_RECALL',
    'status': finished ? 'COMPLETED' : 'DRAFT',
    'answers': [...stored],
    'questions': List.generate(
      2,
      (i) => {
        'entryId': 'word$i',
        'videoUrl': '',
        'imageUrls': <String>[],
        'hint': hints.contains(i)
            ? 'Gồm 2 tiếng, bắt đầu bằng chữ “${words[i][0]}”.'
            : null,
        'response': responses[i],
      },
    ),
    if (finished)
      'result': {
        'source': 'video-recall',
        'summary': {
          'independent': responses.values
              .where((r) => r['match'] == 'EXACT' && r['usedHint'] != true)
              .length,
          'assisted': responses.values
              .where(
                (r) =>
                    r['usedHint'] == true && r['match'] == 'EXACT' ||
                    r['assessment'] == 'SAME_MEANING',
              )
              .length,
          'review': responses.values
              .where(
                (r) => r['match'] == 'SKIPPED' || r['assessment'] == 'REVIEW',
              )
              .length,
        },
        'items': List.generate(
          2,
          (i) => {
            'word': words[i],
            'entryId': 'word$i',
            'selectedAnswer': stored[i],
            'score':
                responses[i]?['match'] == 'EXACT' &&
                    responses[i]?['usedHint'] != true
                ? 10
                : 0,
            'matchStatus': responses[i]?['match'],
            'usedHint': responses[i]?['usedHint'],
            'selfAssessment': responses[i]?['assessment'],
            'definition': 'Nội dung tham khảo đã được lưu.',
            'applied': true,
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
    saves++;
    await saveGate?.future;
    if (failSave) throw ApiException(message: 'Chưa lưu được bài');
    stored = [...answers];
    return snapshot(id);
  }

  int at(String entry) => int.parse(entry.substring(4));
  @override
  Future<LearningRecord> quizHint(String id, String entryId) async {
    hints.add(at(entryId));
    return snapshot(id);
  }

  @override
  Future<LearningRecord> checkQuizAnswer(
    String id,
    String entryId,
    String answer, {
    bool skip = false,
  }) async {
    checks++;
    await checkGate?.future;
    if (failCheck) {
      throw ApiException(message: 'Chưa đối chiếu được, hãy thử lại');
    }
    final i = at(entryId),
        match = skip
            ? 'SKIPPED'
            : matchOverride ??
                  (answer.trim().toLowerCase() == words[i]
                      ? 'EXACT'
                      : 'DIFFERENT');
    stored[i] = answer.trim();
    responses[i] = {
      'answer': answer.trim(),
      'match': match,
      'usedHint': hints.contains(i),
      'assessment': skip ? 'REVIEW' : null,
      'correctAnswer': words[i],
      'definition': 'Nội dung tham khảo đã được lưu.',
      'usageExample': '',
    };
    return snapshot(id);
  }

  @override
  Future<LearningRecord> assessQuizAnswer(
    String id,
    String entryId,
    String assessment,
  ) async {
    responses[at(entryId)]!['assessment'] = assessment;
    return snapshot(id);
  }

  @override
  Future<LearningRecord> submitQuiz(String id) async {
    submits++;
    if (failSubmit) throw ApiException(message: 'Chưa hoàn tất được bài');
    finished = true;
    return snapshot(id);
  }

  @override
  Future<LearningRecord> quizAdvice(String id) {
    adviceCalls++;
    return adviceGate?.future ??
        Future.value({
          'source': 'rules',
          'advice': 'Xem lại mẫu của những từ có hỗ trợ.',
        });
  }
}

class FakeQuizMirror implements QuizMirror {
  Completer<void>? gate;
  bool initialized = false;
  int closes = 0, previews = 0;
  @override
  double get aspectRatio => 3 / 4;
  @override
  Future<void> initialize() async {
    await gate?.future;
    initialized = true;
  }

  @override
  Widget preview() {
    if (!initialized) {
      throw StateError('Preview before initialization');
    }
    previews++;
    return const Text('Gương camera');
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    RecallQuizService service, {
    Size size = const Size(390, 844),
    double scale = 1,
    bool dark = false,
    QuizMirror Function()? mirrorFactory,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      Provider<LearningService>.value(
        value: service,
        child: MaterialApp(
          theme: makeTheme(dark: dark, highContrast: false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: ReviewQuizScreen(
            quizId: 'quiz',
            mirrorFactory: mirrorFactory ?? createQuizMirror,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cta(String text) => find.widgetWithText(AppButton, text);
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String text) async {
    final field = find.byKey(const ValueKey('quiz-recall-answer'));
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  Future<void> check(WidgetTester tester, String text) async {
    await enter(tester, text);
    await tap(tester, cta('Kiểm tra nghĩa'));
  }

  Future<void> finish(WidgetTester tester) async {
    await check(tester, 'xin chào');
    await tap(tester, cta('Từ tiếp'));
    await check(tester, 'bàn bạc');
    await tap(tester, cta('Hoàn tất lượt ôn'));
  }

  testWidgets(
    'recall starts with a labelled field and checks meaning without multiple-choice options',
    (tester) async {
      final service = RecallQuizService();
      await mount(tester, service);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Nghĩa bạn nhớ'), findsOneWidget);
      expect(find.text('xin chào'), findsNothing);
      expect(find.text('Bàn bạc'), findsNothing);
      await tap(tester, cta('Kiểm tra nghĩa'));
      expect(
        find.text('Nhập nghĩa bạn nhớ, hoặc chọn Chưa nhớ.'),
        findsOneWidget,
      );
      expect(service.checks, 0);
      await check(tester, 'xin chào');
      expect(find.text('Bạn đã tự nhớ được'), findsOneWidget);
      expect(find.text('xin chào'), findsOneWidget);
      await tap(tester, cta('Từ tiếp'));
      expect(find.text('Từ 2 / 2'), findsOneWidget);
    },
  );
  testWidgets(
    'hints preserve text drafts and are identified as assisted recall',
    (tester) async {
      final service = RecallQuizService();
      await mount(tester, service);
      await enter(tester, 'xin');
      await tap(tester, find.text('Gợi ý'));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'xin',
      );
      expect(find.textContaining('Gồm 2 tiếng'), findsOneWidget);
      await check(tester, 'xin chào');
      expect(find.text('Bạn đã tìm ra nghĩa'), findsOneWidget);
      expect(
        find.text('Bạn đã dùng gợi ý. Từ này sẽ được ôn lại để củng cố.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'a close answer is never silently accepted and explicit self-assessment enables the next word',
    (tester) async {
      final service = RecallQuizService()..matchOverride = 'CLOSE';
      await mount(tester, service);
      await check(tester, 'xin chao');
      expect(find.text('Cùng đối chiếu'), findsOneWidget);
      expect(tester.widget<AppButton>(cta('Từ tiếp')).onPressed, isNull);
      await tap(tester, cta('Tôi diễn đạt cùng nghĩa'));
      expect(service.responses[0]!['assessment'], 'SAME_MEANING');
      expect(tester.widget<AppButton>(cta('Từ tiếp')).onPressed, isNotNull);
    },
  );
  testWidgets(
    'a skipped word reveals the answer and stays available for review',
    (tester) async {
      final service = RecallQuizService();
      await mount(tester, service);
      await enter(tester, 'Tôi chưa chắc');
      await tap(tester, find.text('Chưa nhớ'));
      expect(find.text('Cùng học lại từ này'), findsOneWidget);
      expect(service.stored[0], 'Tôi chưa chắc');
      expect(service.responses[0]!['match'], 'SKIPPED');
      expect(tester.widget<AppButton>(cta('Từ tiếp')).onPressed, isNotNull);
    },
  );
  testWidgets(
    'failed checks retain input and duplicate taps cannot start concurrent checks',
    (tester) async {
      final service = RecallQuizService()..failCheck = true;
      await mount(tester, service);
      await check(tester, 'xin chào');
      expect(find.text('Chưa đối chiếu được, hãy thử lại'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'xin chào',
      );
      service.failCheck = false;
      service.checkGate = Completer<void>();
      await tester.tap(cta('Kiểm tra nghĩa'));
      await tester.pump();
      expect(service.checks, 2);
      expect(tester.widget<AppButton>(cta('Đang đối chiếu…')).busy, isTrue);
      service.checkGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Bạn đã tự nhớ được'), findsOneWidget);
    },
  );
  testWidgets(
    'resumes the first pending self-assessment and retains first checked answers',
    (tester) async {
      final service = RecallQuizService();
      await service.checkQuizAnswer('quiz', 'word0', 'xin chào');
      await service.checkQuizAnswer('quiz', 'word1', 'khác nghĩa');
      await mount(tester, service);
      expect(find.text('Từ 2 / 2'), findsOneWidget);
      expect(find.text('Cùng đối chiếu'), findsOneWidget);
      await tap(tester, cta('Tôi cần ôn thêm'));
      await tap(tester, cta('Hoàn tất lượt ôn'));
      expect(find.text('Bạn đã hoàn tất lượt ôn'), findsOneWidget);
      expect(find.text('Cần ôn thêm'), findsWidgets);
    },
  );
  testWidgets('save-and-leave protects the current unverified text', (
    tester,
  ) async {
    final service = RecallQuizService();
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
                child: const Text('Mở bài'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở bài'));
    await tester.pumpAndSettle();
    await enter(tester, 'Nội dung đang nhớ');
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Rời bài ôn tập?'), findsOneWidget);
    await tester.tap(find.text('Lưu & thoát'));
    await tester.pumpAndSettle();
    expect(service.stored[0], 'Nội dung đang nhớ');
    expect(find.text('Mở bài'), findsOneWidget);
  });
  testWidgets(
    'both back controls warn even after all entered answers have been saved',
    (tester) async {
      final service = RecallQuizService();
      await mount(tester, service);
      await check(tester, 'xin chào');
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.text('Rời bài ôn tập?'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục ôn'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Rời bài ôn tập?'), findsOneWidget);
      expect(service.saves, 0);
      await tester.tap(find.text('Tiếp tục ôn'));
      await tester.pumpAndSettle();
      expect(find.text('Bạn đã tự nhớ được'), findsOneWidget);
    },
  );
  testWidgets('a failed exit save keeps the draft and the user on the quiz', (
    tester,
  ) async {
    final service = RecallQuizService()..failSave = true;
    await mount(tester, service);
    await enter(tester, 'Nghĩa đang nhớ');
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu & thoát'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa lưu được bài'), findsOneWidget);
    expect(find.text('Nghĩa đang nhớ'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Rời bài ôn tập?'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục ôn'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'comparison hides dataset boilerplate but retains a useful definition',
    (tester) async {
      final service = RecallQuizService();
      await service.checkQuizAnswer('quiz', 'word0', 'khác');
      service.responses[0]!['definition'] =
          'Mẫu ký hiệu tham khảo cho “ai bảo”, theo nhãn trong dataset nguồn.';
      await mount(tester, service);
      expect(find.textContaining('Mẫu ký hiệu tham khảo'), findsNothing);
      await tap(tester, cta('Tôi cần ôn thêm'));
      await tap(tester, cta('Từ tiếp'));
      await check(tester, 'bàn bạc');
      expect(find.text('Nội dung tham khảo đã được lưu.'), findsOneWidget);
    },
  );
  testWidgets(
    'failed final submission can be retried and AI feedback never blocks the saved summary',
    (tester) async {
      final service = RecallQuizService()
        ..failSubmit = true
        ..adviceGate = Completer<LearningRecord>();
      await mount(tester, service);
      await finish(tester);
      expect(find.text('Chưa hoàn tất được bài'), findsOneWidget);
      service.failSubmit = false;
      await tap(tester, cta('Hoàn tất lượt ôn'));
      expect(find.text('Bạn đã hoàn tất lượt ôn'), findsOneWidget);
      final suggestion = cta('Nhận gợi ý ôn tập');
      await tester.ensureVisible(suggestion);
      await tester.tap(suggestion);
      await tester.pump();
      await tester.pump();
      expect(find.text('Tự nhớ'), findsOneWidget);
      expect(cta('Về chủ đề'), findsOneWidget);
      service.adviceGate!.complete({
        'source': 'lm-studio',
        'advice': 'Bạn tự nhớ hai từ. Ôn lại sau ba ngày.',
      });
      await tester.pumpAndSettle();
      expect(find.text('Gợi ý từ LM Studio'), findsOneWidget);
    },
  );
  testWidgets(
    'practice camera is opt-in and is released if closed before initialization completes',
    (tester) async {
      final service = RecallQuizService(),
          mirror = FakeQuizMirror()..gate = Completer<void>();
      var created = 0;
      await mount(
        tester,
        service,
        mirrorFactory: () {
          created++;
          return mirror;
        },
      );
      await check(tester, 'xin chào');
      expect(created, 0);
      await tap(tester, find.text('Tự thực hành với mẫu'));
      expect(
        tester
            .widget<LearningWordContent>(
              find.byKey(const ValueKey('recall-media-word0')),
            )
            .pauseVideo,
        isTrue,
      );
      expect(created, 0);
      final open = cta('Mở camera để soi động tác');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump();
      expect(created, 1);
      expect(mirror.previews, 0);
      await tester.tap(find.byTooltip('Đóng tự thực hành'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LearningWordContent>(
              find.byKey(const ValueKey('recall-media-word0')),
            )
            .pauseVideo,
        isFalse,
      );
      mirror.gate!.complete();
      await tester.pumpAndSettle();
      expect(mirror.closes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'practice camera closes on background and needs an explicit restart',
    (tester) async {
      final service = RecallQuizService(), mirror = FakeQuizMirror();
      await mount(tester, service, mirrorFactory: () => mirror);
      await check(tester, 'xin chào');
      await tap(tester, find.text('Tự thực hành với mẫu'));
      await tap(tester, cta('Mở camera để soi động tác'));
      expect(find.text('Gương camera'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(mirror.closes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Gương camera'), findsNothing);
    },
  );
  testWidgets(
    'Android controls have accessible labels, touch targets and contrast',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, RecallQuizService());
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await check(tester, 'khác');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    },
  );
  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 640),
      const Size(844, 390),
      const Size(800, 1024),
    ]) {
      testWidgets(
        'keyboard, large text and reduced motion fit $size dark=$dark',
        (tester) async {
          final service = RecallQuizService();
          await mount(tester, service, size: size, scale: 2, dark: dark);
          await enter(tester, 'xin chào');
          tester.view.viewInsets = FakeViewPadding(
            bottom: size.height < 500 ? 160 : 260,
          );
          await tester.pumpAndSettle();
          final answer = find.byKey(const ValueKey('quiz-recall-answer'));
          await tester.ensureVisible(answer);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(answer).bottom,
            lessThanOrEqualTo(size.height - (size.height < 500 ? 160 : 260)),
          );
          expect(tester.takeException(), isNull);
          await tap(tester, cta('Kiểm tra nghĩa'));
          tester.view.viewInsets = FakeViewPadding.zero;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Bạn đã tự nhớ được'), findsOneWidget);
          await tester.tap(find.byTooltip('Quay lại'));
          await tester.pumpAndSettle();
          expect(find.text('Rời bài ôn tập?'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Tiếp tục ôn'));
          await tester.pumpAndSettle();
          await tap(tester, cta('Từ tiếp'));
          await check(tester, 'một nghĩa khác');
          expect(find.text('Cùng đối chiếu'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tap(tester, cta('Tôi cần ôn thêm'));
          await tap(tester, cta('Hoàn tất lượt ôn'));
          expect(find.text('Bạn đã hoàn tất lượt ôn'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
