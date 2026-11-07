import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/core/theme.dart';
import 'package:sign_voice/features/learning/match_review_quiz_screen.dart';
import 'package:sign_voice/features/learning/quiz_mode_sheet.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

class MatchService extends LearningService {
  final responses = <String, LearningRecord>{};
  final requestIds = <String>[];
  final processed = <String>{};
  bool loseResponse = false, failSubmit = false, completed = false;
  int submissions = 0;
  Completer<void>? gate;
  String? statusOverride;
  Completer<LearningRecord>? adviceGate;
  LearningRecord snapshot() => jsonDecode(
    jsonEncode({
      '_id': 'match',
      'topicId': 'topic',
      'kind': 'VIDEO_MATCH',
      'status': statusOverride ?? (completed ? 'COMPLETED' : 'DRAFT'),
      'questions': List.generate(
        2,
        (i) => {
          'entryId': 'q$i',
          'round': 0,
          'videoUrl': '',
          'imageUrls': [],
          'response': responses['q$i'],
          'hintOptionId': responses['q$i']?['usedHint'] == true ? 'o$i' : null,
        },
      ),
      'matchOptions': [
        {'value': 'o1', 'label': 'Cảm ơn', 'round': 0},
        {'value': 'o0', 'label': 'Xin chào', 'round': 0},
      ],
      if (completed)
        'result': {
          'gamePoints': 150,
          'summary': {'firstTry': 1, 'practiced': 1},
          'feedback': 'Điểm thưởng tách khỏi mức độ ghi nhớ.',
          'items': List.generate(
            2,
            (i) => {
              'entryId': 'q$i',
              'word': i == 0 ? 'Xin chào' : 'Cảm ơn',
              'feedback': 'Hãy tự nhớ nghĩa ở lượt sau.',
              'applied': true,
            },
          ),
        },
    }),
  ) as LearningRecord;

  @override
  Future<LearningRecord> quiz(String id) async => snapshot();
  @override
  Future<LearningRecord> matchQuizPair(
    String id,
    String entryId,
    String optionId,
    String requestId,
  ) async {
    requestIds.add(requestId);
    await gate?.future;
    if (processed.add(requestId)) {
      final row = responses[entryId];
      final correct = optionId == 'o${entryId.substring(1)}';
      responses[entryId] = {
        'matched': correct,
        'usedHint': row?['usedHint'] == true,
        'firstCorrect': (row?['attempts'] as int? ?? 0) == 0
            ? correct
            : row!['firstCorrect'],
        'attempts': (row?['attempts'] as int? ?? 0) + 1,
        'selectedOptionId': optionId,
      };
    }
    if (loseResponse) {
      loseResponse = false;
      throw ApiException(message: 'Mất phản hồi, hãy gửi lại lượt ghép.');
    }
    return snapshot();
  }

  @override
  Future<LearningRecord> matchQuizHint(String id, String entryId) async {
    responses[entryId] = {...?(responses[entryId]), 'usedHint': true};
    return snapshot();
  }

  @override
  Future<LearningRecord> submitQuiz(String id) async {
    submissions++;
    if (failSubmit) {
      throw ApiException(message: 'Chưa lưu được kết quả, hãy nộp lại.');
    }
    completed = true;
    return snapshot();
  }

  @override
  Future<LearningRecord> quizAdvice(String id) =>
      adviceGate?.future ??
      Future.value({
        'source': 'rules',
        'advice': 'Xem lại mẫu rồi thử tự nhớ nghĩa.',
      });
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    MatchService service, {
    Size size = const Size(1100, 900),
    double textScale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      Provider<LearningService>.value(
        value: service,
        child: MaterialApp(
          theme: makeTheme(dark: dark, highContrast: false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const MatchReviewQuizScreen(quizId: 'match'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapPair(WidgetTester tester, String option, String entry) async {
    await tester.tap(find.byKey(ValueKey('match-option-$option')));
    await tester.pumpAndSettle();
    final target = find.byKey(ValueKey('match-target-$entry'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tap matching permits retry, preserves first result, and submits with hints',
    (tester) async {
      final service = MatchService();
      await mount(tester, service);
      await tapPair(tester, 'o1', 'q0');
      expect(find.textContaining('Chưa khớp.'), findsOneWidget);
      await tapPair(tester, 'o0', 'q0');
      expect(service.responses['q0'], containsPair('firstCorrect', false));
      await tester.tap(find.byTooltip('Gợi ý mẫu 2'));
      await tester.pumpAndSettle();
      expect(find.text('Gợi ý: Cảm ơn'), findsOneWidget);
      await tapPair(tester, 'o1', 'q1');
      expect(find.text('Hoàn tất và lưu kết quả'), findsOneWidget);
      service.failSubmit = true;
      await tester.ensureVisible(find.text('Hoàn tất và lưu kết quả'));
      await tester.tap(find.text('Hoàn tất và lưu kết quả'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa lưu được kết quả'), findsOneWidget);
      expect(service.completed, isFalse);
      service.failSubmit = false;
      await tester.ensureVisible(find.text('Hoàn tất và lưu kết quả'));
      await tester.tap(find.text('Hoàn tất và lưu kết quả'));
      await tester.pumpAndSettle();
      expect(find.text('Hoàn thành lượt ghép cặp!'), findsOneWidget);
      expect(find.text('150 điểm thưởng'), findsOneWidget);
      expect(service.submissions, 2);
      service.adviceGate = Completer<LearningRecord>();
      await tester.ensureVisible(find.text('Nhận gợi ý ôn tập'));
      await tester.tap(find.text('Nhận gợi ý ôn tập'));
      await tester.pump();
      expect(find.text('150 điểm thưởng'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Quay lại',
              ),
            )
            .onPressed,
        isNotNull,
      );
      service.adviceGate!.complete({
        'source': 'rules',
        'advice': 'Xem lại mẫu rồi thử tự nhớ nghĩa.',
      });
      await tester.pumpAndSettle();
      expect(find.text('Xem lại mẫu rồi thử tự nhớ nghĩa.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging a word to a sample checks the pair on the server', (
    tester,
  ) async {
    final service = MatchService();
    await mount(tester, service);
    final start = tester.getCenter(
      find.byKey(const ValueKey('match-option-o0')),
    );
    final target = tester.getCenter(
      find.byKey(const ValueKey('match-target-q0')),
    );
    await tester.dragFrom(start, target - start);
    await tester.pumpAndSettle();
    expect(service.responses['q0'], containsPair('matched', true));
    expect(service.requestIds, hasLength(1));
  });

  testWidgets(
    'lost response retries with the same request ID without adding an attempt',
    (tester) async {
      final service = MatchService()..loseResponse = true;
      await mount(tester, service);
      await tapPair(tester, 'o0', 'q0');
      expect(find.text('Gửi lại lượt ghép'), findsOneWidget);
      final other = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('match-option-o1')),
      );
      expect(other.onPressed, isNull);
      await tester.tap(find.text('Gửi lại lượt ghép'));
      await tester.pumpAndSettle();
      expect(service.requestIds, hasLength(2));
      expect(service.requestIds.toSet(), hasLength(1));
      expect(service.responses['q0']?['attempts'], 1);
      await tester.tap(find.byTooltip('Tải trạng thái đã lưu'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Đã ghép 1/2'), findsOneWidget);
    },
  );

  testWidgets(
    'disables navigation and repeated input during a pending server mutation',
    (tester) async {
      final service = MatchService()..gate = Completer<void>();
      await mount(tester, service);
      await tester.tap(find.byKey(const ValueKey('match-option-o0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('match-target-q0')));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Quay lại',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('match-option-o1')),
            )
            .onPressed,
        isNull,
      );
      expect(service.requestIds, hasLength(1));
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(service.responses['q0']?['matched'], isTrue);
    },
  );

  testWidgets('mobile layout fits without overflow', (tester) async {
    final service = MatchService();
    await mount(tester, service, size: const Size(360, 800));
    expect(tester.takeException(), isNull);
    await tapPair(tester, 'o0', 'q0');
    expect(service.responses['q0']?['matched'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode picker offers matching and retains recall', (tester) async {
    String? mode;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                mode = await chooseQuizMode(context);
              },
              child: const Text('Ôn tập'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ôn tập'));
    await tester.pumpAndSettle();
    expect(find.text('Tự nhớ nghĩa'), findsOneWidget);
    await tester.tap(find.text('Ghép cặp ký hiệu'));
    await tester.pumpAndSettle();
    expect(mode, 'VIDEO_MATCH');
  });

  testWidgets('invalidated library draft cannot keep accepting pairs', (
    tester,
  ) async {
    await mount(tester, MatchService()..statusOverride = 'ABANDONED');
    expect(find.textContaining('Lượt này không còn khả dụng'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(DragTarget<String>), findsNothing);
  });

  for (final dark in [false, true]) {
    for (final size in [const Size(320, 640), const Size(844, 390)]) {
      testWidgets(
        'matching fits text 2x $size dark=$dark with completed round',
        (tester) async {
          final service = MatchService();
          for (var i = 0; i < 2; i++) {
            service.responses['q$i'] = {
              'matched': true,
              'firstCorrect': true,
              'usedHint': false,
              'attempts': 1,
              'selectedOptionId': 'o$i',
            };
          }
          await mount(tester, service, size: size, textScale: 2, dark: dark);
          expect(find.text('Hoàn tất và lưu kết quả'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
