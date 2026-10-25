import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import 'auth_fixtures.dart';

class HistoryService extends DemoLearningService {
  final calls = <LearningRecord>[];
  @override
  Future<LearningPage> history({
    int page = 1,
    String search = '',
    String? entryId,
  }) async {
    calls.add({'page': page, 'search': search, 'entryId': entryId});
    final all =
        List.generate(
              11,
              (i) => <String, dynamic>{
                '_id': '$i',
                'entryId': '${i + 10}'.padLeft(24, '0'),
                'word': 'History word $i',
                'topicName': 'Chào hỏi',
                'kind': i == 0 ? 'RECORDED_PROGRESS' : 'SELF_RATED',
                'stage': 'REMEMBERED',
                'createdAt': '2026-10-25T08:00:00.000Z',
              },
            )
            .where(
              (e) =>
                  (entryId == null || e['entryId'] == entryId) &&
                  '${e['word']}'.contains(search),
            )
            .toList();
    return LearningPage(
      items: all.skip((page - 1) * 10).take(10).toList(),
      page: page,
      pages: (all.length / 10).ceil().clamp(1, 100),
      total: all.length,
    );
  }
}

Future<void> mountHistory(
  WidgetTester tester,
  HistoryService service,
  String route,
) async {
  final auth = await authenticatedProvider();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    SignVoiceApp(
      auth: auth,
      state: AppState(),
      learningService: service,
      initialScreen: route,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an enrolled word opens its own timeline', (tester) async {
    final service = HistoryService()..enrolled = true;
    await mountHistory(
      tester,
      service,
      '/learn/topic/${DemoLearningService.topicId}?study=1',
    );
    final link = find.text('Lịch sử từ này').first;
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(service.calls.last['entryId'], '000000000000000000000010');
    expect(find.text('History word 0'), findsOneWidget);
  });

  testWidgets('history opens from studying and searches recorded words', (
    tester,
  ) async {
    final service = HistoryService()..enrolled = true;
    await mountHistory(tester, service, '/learn?tab=1');
    final history = find.text('Lịch sử học tập');
    await tester.ensureVisible(history);
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.text('History word 0'), findsOneWidget);
    expect(find.text('Trạng thái đã lưu'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'word 10');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('History word 10'), findsOneWidget);
    expect(find.text('History word 0'), findsNothing);
    expect(service.calls.last, {
      'page': 1,
      'search': 'word 10',
      'entryId': null,
    });
  });

  testWidgets('word history route passes the selected entry filter', (
    tester,
  ) async {
    final service = HistoryService();
    await mountHistory(
      tester,
      service,
      '/learn/history?entryId=000000000000000000000010',
    );
    expect(service.calls.single['entryId'], '000000000000000000000010');
    expect(find.text('History word 0'), findsOneWidget);
    expect(find.text('History word 1'), findsNothing);
  });

  testWidgets('history requests the next ten records', (tester) async {
    final service = HistoryService();
    await mountHistory(tester, service, '/learn/history');
    await tester.ensureVisible(find.byTooltip('Trang sau'));
    await tester.tap(find.byTooltip('Trang sau'));
    await tester.pumpAndSettle();
    expect(service.calls.last['page'], 2);
    expect(find.text('History word 10'), findsOneWidget);
  });
}
