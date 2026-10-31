import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';

import 'auth_fixtures.dart';

class PendingCoachService extends DemoLearningService {
  final response = Completer<LearningRecord>();
  @override
  Future<LearningRecord> coach() => response.future;
}

void main() {
  for (final source in ['lm-studio', 'rules']) {
    testWidgets(
      'dev learning UI labels $source advice without changing progress',
      (tester) async {
        final auth = await authenticatedProvider();
        addTearDown(auth.dispose);
        final service = PendingCoachService()..enrolled = true;
        service.ratings['000000000000000000000010'] = 'REMEMBERED';
        final before = Map<String, String>.from(service.ratings);
        await tester.pumpWidget(
          SignVoiceApp(
            auth: auth,
            state: AppState(),
            learningService: service,
            initialScreen: '/learn?tab=1',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Khám phá'), findsOneWidget);
        expect(find.text('Đang học'), findsWidgets);
        expect(find.text('Bộ sưu tập'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Gợi ý ôn tập'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Gợi ý ôn tập'));
        await tester.pump();
        service.response.complete({
          'source': source,
          'advice': 'Ôn lại nhóm từ cần luyện tập.',
        });
        await tester.pumpAndSettle();
        expect(find.text('Ôn lại nhóm từ cần luyện tập.'), findsOneWidget);
        expect(
          find.text(
            source == 'lm-studio'
                ? 'Gợi ý từ LM Studio'
                : 'Lộ trình ôn tập cơ bản',
          ),
          findsOneWidget,
        );
        expect(service.ratings, before);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('coach waits for a slow model and uses the new learning API', (
    tester,
  ) async {
    http.Request? sent;
    var ready = false;
    final transport = MockClient((request) async {
      if (request.method == 'POST') {
        sent = request;
        Timer(const Duration(seconds: 45), () => ready = true);
        return http.Response(
          '{"data":{"id":"slow-coach","state":"pending"}}',
          202,
        );
      }
      return http.Response(
        jsonEncode({
          'success': true,
          'data': ready
              ? {
                  'id': 'slow-coach',
                  'state': 'completed',
                  'result': {
                    'source': 'lm-studio',
                    'advice': 'Ôn lại nhóm từ cần luyện tập.',
                  },
                }
              : {'id': 'slow-coach', 'state': 'pending'},
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
    final service = LearningService(client: client);
    LearningRecord? result;
    Object? failure;
    final pending = service.coach().then<void>(
      (value) {
        result = value;
      },
      onError: (Object error) {
        failure = error;
      },
    );
    await tester.pump();
    expect(sent?.method, 'POST');
    expect(sent?.url.path, endsWith('/learning/coach'));
    expect(jsonDecode(sent!.body)['async'], true);
    await tester.pump(const Duration(seconds: 31));
    expect(failure, isNull);
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(seconds: 3));
    await pending;
    expect(result?['source'], 'lm-studio');
    expect(result?['advice'], contains('Ôn lại'));
    client.dispose();
  });
}
