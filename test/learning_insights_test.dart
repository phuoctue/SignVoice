import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/features/learning/learning_activity_chart.dart';
import 'package:sign_voice/features/learning/learning_daily_goals.dart';

import 'auth_fixtures.dart';

class InsightsService extends DemoLearningService {
  final requests = <List<int>>[];
  int newDone = 1, reviewDone = 3, todayCalls = 0;
  bool failToday = false;
  final dayRequests = <LearningRecord>[];
  LearningRecord goals = {'newWords': 5, 'reviewWords': 10};
  @override
  Future<LearningRecord> insights({int days = 7, int page = 1}) async {
    requests.add([days, page]);
    return {
      'days': days,
      'timeZone': 'Asia/Ho_Chi_Minh',
      'activity': List.generate(
        days,
        (i) => {
          'date': DateTime(2026, 10, 25)
              .subtract(Duration(days: days - 1 - i))
              .toIso8601String()
              .substring(0, 10),
          'learned': i == days - 1 ? 2 : 0,
          'newWords': i == days - 1 ? 1 : 0,
          'reviewed': i == days - 1 ? 3 : 0,
        },
      ),
      'today': {
        'date': '2026-10-25',
        'learned': newDone > 2 ? newDone : 2,
        'newWords': newDone,
        'reviewed': reviewDone,
      },
      'goals': goals,
      'weakWords': {
        'items': [
          {
            '_id': 'word',
            'entryId': '000000000000000000000010',
            'topicId': DemoLearningService.topicId,
            'word': 'Xin chào',
            'definition': 'Lời chào',
            'topicName': 'Chào hỏi',
            'misses': 2,
            'attempts': 3,
            'missRate': 67,
            'latestMatched': false,
          },
        ],
        'pagination': {'page': page, 'pages': 2, 'total': 11},
      },
    };
  }

  @override
  Future<void> saveGoals({
    required int newWords,
    required int reviewWords,
  }) async {
    goals = {'newWords': newWords, 'reviewWords': reviewWords};
  }

  @override
  Future<LearningRecord> todayProgress() async {
    todayCalls++;
    if (failToday) throw ApiException(message: 'Mất kết nối đồng bộ');
    return {
      'today': {
        'date': '2026-10-25',
        'learned': newDone > 2 ? newDone : 2,
        'newWords': newDone,
        'reviewed': reviewDone,
      },
      'goals': goals,
    };
  }

  @override
  Future<LearningPage> activity({
    required String date,
    String kind = 'learned',
    int page = 1,
  }) async {
    dayRequests.add({'date': date, 'kind': kind, 'page': page});
    return LearningPage(
      items: [
        {
          'entryId': '000000000000000000000010',
          'word': kind == 'learned'
              ? 'Từ học ngày được chọn'
              : 'Từ ôn ngày được chọn',
          'topicName': 'Chào hỏi',
          'occurredAt': '2026-10-25T08:00:00Z',
          'stage': 'REMEMBERED',
          'matched': true,
        },
      ],
      total: 1,
    );
  }
}

class FailingGoalService extends InsightsService {
  bool fail = true;
  @override
  Future<void> saveGoals({
    required int newWords,
    required int reviewWords,
  }) async {
    if (fail) throw ApiException(message: 'Chưa kết nối, hãy thử lại.');
    await super.saveGoals(newWords: newWords, reviewWords: reviewWords);
  }
}

class FailingInsightsService extends InsightsService {
  bool fail = true;
  @override
  Future<LearningRecord> insights({int days = 7, int page = 1}) async {
    if (fail) {
      throw ApiException(message: 'Chưa tải được số liệu, hãy thử lại.');
    }
    return super.insights(days: days, page: page);
  }
}

class PendingInsightsService extends InsightsService {
  final ready = Completer<void>();
  @override
  Future<LearningRecord> insights({int days = 7, int page = 1}) async {
    await ready.future;
    return super.insights(days: days, page: page);
  }
}

void main() {
  testWidgets(
    'goals refresh manually without periodic requests and turn green',
    (tester) async {
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      final service = InsightsService();
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          state: AppState(),
          learningService: service,
          initialScreen: '/learn/insights',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đã ôn 3/10 từ'), findsOneWidget);
      service.newDone = 5;
      service.reviewDone = 10;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(service.todayCalls, 0);
      expect(service.requests.length, 1);
      await tester.tap(find.byTooltip('Làm mới'));
      await tester.pumpAndSettle();
      expect(find.text('Đã ôn 10/10 từ'), findsOneWidget);
      expect(find.text('Hoàn thành mục tiêu ôn'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Đã ôn 10/10 từ')).style!.color,
        const Color(0xFF15803D),
      );
      expect(
        find.text('Bạn đã hoàn thành cả hai mục tiêu hôm nay!'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('completed goals fit narrow screens and reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2.5),
              disableAnimations: true,
            ),
            child: SingleChildScrollView(
              child: LearningDailyGoals(
                today: const {
                  'date': '2026-10-25',
                  'newWords': 105,
                  'reviewed': 210,
                },
                goals: const {'newWords': 100, 'reviewWords': 200},
                onEdit: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Đã ôn 210/200 từ'), findsOneWidget);
  });
  testWidgets('tapping a chart day opens studied and reviewed word lists', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final service = InsightsService();
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        learningService: service,
        initialScreen: '/learn/insights',
      ),
    );
    await tester.pumpAndSettle();
    final day = find.byTooltip('2026-10-25: học 2, ôn 3');
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.text('Từ học ngày được chọn'), findsOneWidget);
    await tester.tap(find.text('Đã ôn'));
    await tester.pumpAndSettle();
    expect(find.text('Từ ôn ngày được chọn'), findsOneWidget);
    expect(service.dayRequests.last['date'], '2026-10-25');
    expect(service.dayRequests.last['kind'], 'reviewed');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('day details close when the account signs out', (tester) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final service = InsightsService();
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        learningService: service,
        initialScreen: '/learn/insights',
      ),
    );
    await tester.pumpAndSettle();
    final day = find.byTooltip('2026-10-25: học 2, ôn 3');
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(find.text('Từ học ngày được chọn'), findsOneWidget);
    await auth.logout();
    await tester.pumpAndSettle();
    expect(find.text('Từ học ngày được chọn'), findsNothing);
    expect(find.byTooltip('Đóng'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('insights fetch can be retried without showing invented counts', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final service = FailingInsightsService();
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        learningService: service,
        initialScreen: '/learn/insights',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa tải được số liệu, hãy thử lại.'), findsOneWidget);
    expect(find.text('Đã học 1/5 từ mới'), findsNothing);
    service.fail = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Đã học 1/5 từ mới'), findsOneWidget);
  });
  testWidgets('pending insights cannot update a page after navigating back', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final service = PendingInsightsService()..enrolled = true;
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        learningService: service,
        initialScreen: '/learn?tab=1',
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Thống kê & mục tiêu'));
    await tester.tap(find.text('Thống kê & mục tiêu'));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    service.ready.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Mục tiêu hôm nay'), findsNothing);
  });
  testWidgets('failed goal save keeps typed input and supports retry', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final service = FailingGoalService();
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        learningService: service,
        initialScreen: '/learn/insights',
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Đổi mục tiêu'));
    await tester.tap(find.text('Đổi mục tiêu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '7');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa kết nối, hãy thử lại.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '7',
    );
    expect(service.goals['newWords'], 5);
    service.fail = false;
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Đã học 1/7 từ mới'), findsOneWidget);
  });

  testWidgets('reinforcement list paginates and changing period resets page', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final service = InsightsService();
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        learningService: service,
        initialScreen: '/learn/insights',
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Trang sau'));
    await tester.tap(find.byTooltip('Trang sau'));
    await tester.pumpAndSettle();
    expect(service.requests.last, [7, 2]);
    await tester.ensureVisible(find.byType(DropdownButton<int>));
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 ngày').last);
    await tester.pumpAndSettle();
    expect(service.requests.last, [30, 1]);
  });

  testWidgets(
    '30-day chart fits 360px large text and selecting a day updates details',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = await InsightsService().insights(days: 30);
      final activity = (data['activity'] as List).cast<LearningRecord>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2.5),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: LearningActivityChart(days: activity),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Ngày 2026-10-25: học 2 từ · ôn 3 từ'), findsOneWidget);
      await tester.tap(find.byTooltip('2026-10-24: học 0, ôn 0'));
      await tester.pumpAndSettle();
      expect(find.text('Ngày 2026-10-24: học 0 từ · ôn 0 từ'), findsOneWidget);
    },
  );

  testWidgets(
    'insights opens from studying, switches period and shows real goal counts',
    (tester) async {
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      final service = InsightsService()..enrolled = true;
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          state: AppState(),
          learningService: service,
          initialScreen: '/learn?tab=1',
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Thống kê & mục tiêu'));
      await tester.tap(find.text('Thống kê & mục tiêu'));
      await tester.pumpAndSettle();
      expect(find.text('Đã học 1/5 từ mới'), findsOneWidget);
      expect(find.text('Đã ôn 3/10 từ'), findsOneWidget);
      await tester.ensureVisible(find.byType(DropdownButton<int>));
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 ngày').last);
      await tester.pumpAndSettle();
      expect(service.requests.last, [30, 1]);
      expect(find.text('2 / 3 lượt chưa khớp (67%)'), findsOneWidget);
    },
  );
  testWidgets('daily goals can be edited and invalid numbers are rejected', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final service = InsightsService();
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        learningService: service,
        initialScreen: '/learn/insights',
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Đổi mục tiêu'));
    await tester.tap(find.text('Đổi mục tiêu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(service.goals['newWords'], 5);
    await tester.enterText(find.byType(TextFormField).first, '7');
    await tester.enterText(find.byType(TextFormField).last, '12');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(service.goals, {'newWords': 7, 'reviewWords': 12});
    expect(find.text('Đã học 1/7 từ mới'), findsOneWidget);
  });
}
