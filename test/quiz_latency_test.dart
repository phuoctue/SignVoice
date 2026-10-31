import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import 'auth_fixtures.dart';

void main() {
  test(
    'starting a quiz hands its result to the screen without a second GET, once',
    () async {
      var gets = 0;
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((request) async {
          if (request.method == 'GET') gets++;
          return http.Response(
            jsonEncode({
              'data': {
                '_id': 'one',
                'kind': 'VIDEO_RECALL',
                'status': 'DRAFT',
                'answers': [''],
                'questions': [],
              },
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final service = LearningService(client: api);
      final started = await service.startQuiz('topic');
      expect(await service.quiz('one'), equals(started));
      expect(gets, 0);
      await service.quiz('one');
      expect(gets, 1);
    },
  );
  test('the one-use quiz response never crosses an account change', () async {
    var gets = 0;
    final api = ApiClient(
      tokenStorage: MemoryTokenStore(),
      client: MockClient((request) async {
        if (request.method == 'GET') gets++;
        return http.Response(
          jsonEncode({
            'data': {
              '_id': 'one',
              'owner': request.method == 'GET' ? 'new' : 'old',
            },
          }),
          200,
        );
      }),
    );
    addTearDown(api.dispose);
    final service = LearningService(client: api);
    await service.startQuiz('topic');
    api.beginAuthentication();
    expect((await service.quiz('one'))['owner'], 'new');
    expect(gets, 1);
  });
  test(
    'a late quiz start from an old account cannot seed the new account',
    () async {
      final gate = Completer<http.Response>();
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((_) => gate.future),
      );
      addTearDown(api.dispose);
      final service = LearningService(client: api);
      final pending = service.startQuiz('topic');
      final rejected = expectLater(
        pending,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      api.beginAuthentication();
      gate.complete(http.Response('{"data":{"_id":"old"}}', 200));
      await rejected;
    },
  );
}
