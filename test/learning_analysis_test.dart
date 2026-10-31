import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/features/learning/learning_analysis_card.dart';

import 'auth_fixtures.dart';

class AnalysisService extends DemoLearningService {
  final response = Completer<LearningRecord>();
  int analyses = 0;
  @override
  Future<LearningRecord> collectionRead(
    String path, {
    int page = 1,
    String search = '',
  }) async => {
    'items': <LearningRecord>[],
    'pagination': {'total': 0, 'page': page, 'pages': 0},
  };
  @override
  Future<LearningRecord> analyzeProgress() {
    analyses++;
    return response.future;
  }
}

LearningRecord analysisResult(String source) => {
  'source': source,
  'summary': {
    'total': 22,
    'learning': 19,
    'remembered': 1,
    'review': 2,
    'topicCount': 11,
    'rememberedPercent': 5,
  },
  'topics': [
    {
      'name': 'Chào hỏi',
      'total': 2,
      'remembered': 1,
      'learning': 0,
      'review': 1,
      'rememberedPercent': 50,
    },
  ],
  'analysis': 'Bạn cần củng cố các chủ đề có nhiều từ đang học.',
  'generatedAt': '2026-10-25T00:00:00.000Z',
};

void main() {
  Future<AnalysisService> mountAnalysis(WidgetTester tester) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    final service = AnalysisService()..enrolled = true;
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        learningService: service,
        initialScreen: '/learn?tab=1',
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Phân tích tiến độ cá nhân'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phân tích tiến độ cá nhân'));
    await tester.pump();
    return service;
  }

  testWidgets('analysis failure keeps the existing coach usable', (
    tester,
  ) async {
    final service = await mountAnalysis(tester);
    service.response.completeError(
      ApiException(message: 'Vui lòng thử lại sau một phút.', statusCode: 429),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng thử lại sau một phút.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Gợi ý ôn tập'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Gợi ý ôn tập'));
    await tester.pumpAndSettle();
    expect(find.text('Lộ trình ôn tập cơ bản'), findsOneWidget);
    expect(service.ratings, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changing tabs discards a pending stale analysis', (
    tester,
  ) async {
    final service = await mountAnalysis(tester);
    await tester.scrollUntilVisible(
      find.text('Bộ sưu tập'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Bộ sưu tập'));
    await tester.pumpAndSettle();
    service.response.complete(analysisResult('lm-studio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đang học').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Bạn cần củng cố các chủ đề có nhiều từ đang học.'),
      findsNothing,
    );
    expect(find.text('Phân tích tiến độ cá nhân'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('analysis card wraps long topics at 360px and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = analysisResult('rules');
    (result['topics'] as List)[0]['name'] =
        'Chủ đề giao tiếp, văn hóa và những tình huống sinh hoạt hằng ngày';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.8),
            ),
            child: SingleChildScrollView(
              child: LearningAnalysisCard(result: result),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final source in ['lm-studio', 'rules']) {
    testWidgets('personal analysis is separate from working coach ($source)', (
      tester,
    ) async {
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      final service = AnalysisService()..enrolled = true;
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          state: AppState(),
          learningService: service,
          initialScreen: '/learn?tab=1',
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Gợi ý ôn tập'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Gợi ý ôn tập'), findsOneWidget);
      final action = find.text('Phân tích tiến độ cá nhân');
      await tester.scrollUntilVisible(
        action,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(action);
      await tester.pump();
      expect(service.analyses, 1);
      service.response.complete(analysisResult(source));
      await tester.pumpAndSettle();
      expect(find.text('Đã nhớ 1 / 22 từ (5%)'), findsOneWidget);
      expect(find.text('11 chủ đề đã bắt đầu'), findsOneWidget);
      expect(
        find.text(
          source == 'lm-studio'
              ? 'Phân tích từ LM Studio'
              : 'Phân tích từ số liệu',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Bạn cần củng cố các chủ đề có nhiều từ đang học.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Gợi ý ôn tập'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Gợi ý ôn tập'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('analysis polls short requests while a 45 second model runs', (
    tester,
  ) async {
    http.Request? sent;
    var ready = false;
    final pollPaths = <String>[];
    final transport = MockClient((request) async {
      if (request.method == 'POST') {
        sent = request;
        Timer(const Duration(seconds: 45), () => ready = true);
        return http.Response(
          '{"data":{"id":"slow-analysis","state":"pending"}}',
          202,
        );
      }
      pollPaths.add(request.url.path);
      return http.Response(
        jsonEncode({
          'success': true,
          'data': ready
              ? {
                  'id': 'slow-analysis',
                  'state': 'completed',
                  'result': analysisResult('lm-studio'),
                }
              : {'id': 'slow-analysis', 'state': 'pending'},
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final client = ApiClient(
      client: transport,
      tokenStorage: MemoryTokenStore(),
      useRefreshCookie: false,
    );
    LearningRecord? result;
    Object? error;
    final pending = LearningService(client: client)
        .analyzeProgress()
        .then<void>(
          (value) {
            result = value;
          },
          onError: (Object failure) {
            error = failure;
          },
        );
    await tester.pump();
    expect(sent?.url.path, endsWith('/learning/analysis'));
    expect(sent?.method, 'POST');
    await tester.pump(const Duration(seconds: 31));
    expect(error, isNull);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 3));
    await pending;
    expect(result?['source'], 'lm-studio');
    expect(pollPaths, isNotEmpty);
    expect(
      pollPaths,
      everyElement(endsWith('/learning/ai-jobs/slow-analysis')),
    );
    client.dispose();
  });
}
