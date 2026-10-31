import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import 'auth_fixtures.dart';

http.Response pageResponse(String word) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'data': {
        'items': [
          {'_id': 'one', 'word': word},
        ],
        'pagination': {'total': 1},
      },
    }),
  ),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets(
    'AI recovers lost start and poll responses without rerunning the job',
    (tester) async {
      final starts = <Map<String, dynamic>>[];
      final pollPaths = <String>[];
      var polls = 0;
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((request) async {
          if (request.method == 'POST') {
            starts.add(jsonDecode(request.body) as Map<String, dynamic>);
            if (starts.length == 1) {
              throw http.ClientException(
                'Mobile connection dropped after start',
              );
            }
            return http.Response(
              '{"data":{"id":"same-job","state":"pending"}}',
              202,
            );
          }
          polls++;
          pollPaths.add(request.url.path);
          if (polls == 1) {
            throw http.ClientException('Brief network interruption');
          }
          return http.Response(
            '{"data":{"id":"same-job","state":"completed","result":{"source":"lm-studio"}}}',
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      LearningRecord? result;
      final pending = LearningService(client: api)
          .analyzeProgress()
          .then((value) => result = value);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await pending;
      expect(result?['source'], 'lm-studio');
      expect(starts.length, 2);
      expect(starts[0]['requestKey'], starts[1]['requestKey']);
      expect(starts[0]['requestKey'], matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(polls, 2);
      expect(pollPaths, everyElement(endsWith('/learning/ai-jobs/same-job')));
    },
  );
  testWidgets('AI polling stops before sending another request after logout', (
    tester,
  ) async {
    var calls = 0;
    final api = ApiClient(
      tokenStorage: MemoryTokenStore(),
      client: MockClient((_) async {
        calls++;
        return http.Response(
          '{"data":{"id":"old-job","state":"pending"}}',
          202,
        );
      }),
    );
    addTearDown(api.dispose);
    final pending = LearningService(client: api).analyzeProgress();
    final rejected = expectLater(
      pending,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await tester.pump();
    api.beginAuthentication();
    await tester.pump(const Duration(seconds: 4));
    await rejected;
    expect(calls, 1);
  });
  for (final feature in ['analysis', 'coach']) {
    test(
      '$feature coalesces active generations, isolates results and refreshes later',
      () async {
        final reply = Completer<http.Response>();
        var calls = 0;
        final api = ApiClient(
          tokenStorage: MemoryTokenStore(),
          client: MockClient((_) {
            calls++;
            return reply.future;
          }),
        );
        addTearDown(api.dispose);
        final service = LearningService(client: api);
        Future<LearningRecord> run() =>
            feature == 'analysis' ? service.analyzeProgress() : service.coach();
        final first = run(), second = run();
        await Future<void>.delayed(Duration.zero);
        expect(calls, 1);
        reply.complete(
          http.Response(
            '{"data":{"source":"lm-studio","summary":{"total":10}}}',
            200,
          ),
        );
        final a = await first, b = await second;
        a['summary']['total'] = 99;
        expect(b['summary']['total'], 10);
        await run();
        expect(calls, 2);
      },
    );
  }
  test(
    'learning AI requests never cross account or progress changes',
    () async {
      final replies = <Completer<http.Response>>[];
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((_) {
          final reply = Completer<http.Response>();
          replies.add(reply);
          return reply.future;
        }),
      );
      addTearDown(api.dispose);
      final service = LearningService(client: api);
      final original = service.analyzeProgress();
      final originalRejected = expectLater(
        original,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'LEARNING_CHANGED'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      service.invalidatePages();
      final changed = service.analyzeProgress();
      final changedRejected = expectLater(
        changed,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      replies[0].complete(http.Response('{"data":{}}', 200));
      await originalRejected;
      api.beginAuthentication();
      final current = service.analyzeProgress();
      await Future<void>.delayed(Duration.zero);
      expect(replies.length, 3);
      replies[1].complete(http.Response('{"data":{}}', 200));
      replies[2].complete(http.Response('{"data":{"source":"current"}}', 200));
      await changedRejected;
      expect((await current)['source'], 'current');
    },
  );
  test(
    'simultaneous and repeated reads share one request; refresh invalidates',
    () async {
      var reads = 0;
      final response = Completer<http.Response>();
      final client = ApiClient(
        client: MockClient((_) async {
          reads++;
          return response.future;
        }),
        tokenStorage: MemoryTokenStore(),
      );
      final service = LearningService(client: client);
      final a = service.topics(), b = service.topics();
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      response.complete(pageResponse('xin chào'));
      expect(identical(await a, await b), isTrue);
      expect(identical(await a, await service.topics()), isTrue);
      expect(
        service.cachedPage('topics', {'page': '1', 'search': ''}),
        isNotNull,
      );
      expect(reads, 1);
      service.invalidatePages();
      expect(service.cachedPage('topics', {'page': '1', 'search': ''}), isNull);
      await service.topics();
      expect(reads, 2);
    },
  );

  test(
    'account changes discard cached pages and reject late old responses',
    () async {
      final late = Completer<http.Response>();
      var reads = 0;
      final client = ApiClient(
        client: MockClient((_) async {
          return ++reads == 1 ? pageResponse('tài khoản cũ') : late.future;
        }),
        tokenStorage: MemoryTokenStore(),
      );
      final service = LearningService(client: client);
      await service.topics();
      final pending = service.topic('one');
      final rejected = expectLater(
        pending,
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      client.beginAuthentication();
      expect(service.cachedPage('topics', {'page': '1', 'search': ''}), isNull);
      late.complete(pageResponse('không được hiện'));
      await rejected;
      expect(
        service.cachedPage('topics/one', {'page': '1', 'stage': 'ALL'}),
        isNull,
      );
    },
  );

  test(
    'acknowledged writes invalidate; failed writes preserve cached progress',
    () async {
      var failWrite = true;
      var reads = 0;
      final client = ApiClient(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            reads++;
            return pageResponse('xin chào');
          }
          return http.Response('{}', failWrite ? 503 : 200);
        }),
        tokenStorage: MemoryTokenStore(),
      );
      final service = LearningService(client: client);
      await service.topics();
      await expectLater(
        service.rate('one', 'REMEMBERED'),
        throwsA(isA<ApiException>()),
      );
      await service.topics();
      expect(reads, 1);
      failWrite = false;
      await service.rate('one', 'REMEMBERED');
      await service.topics();
      expect(reads, 2);
    },
  );

  test(
    'a read started before a write cannot restore stale cached progress',
    () async {
      final stale = Completer<http.Response>();
      var reads = 0;
      final client = ApiClient(
        client: MockClient((request) async {
          if (request.method != 'GET') return http.Response('{}', 200);
          return ++reads == 1 ? stale.future : pageResponse('mới');
        }),
        tokenStorage: MemoryTokenStore(),
      );
      final service = LearningService(client: client);
      final pending = service.topics();
      await Future<void>.delayed(Duration.zero);
      await service.rate('one', 'REVIEW');
      stale.complete(pageResponse('cũ'));
      expect((await pending).items.single['word'], 'mới');
      expect((await service.topics()).items.single['word'], 'mới');
      expect(reads, 2);
    },
  );

  test('private word images are not retained as cached pages', () async {
    var reads = 0;
    final service = LearningService(
      client: ApiClient(
        client: MockClient((_) async {
          reads++;
          return pageResponse('riêng tư');
        }),
        tokenStorage: MemoryTokenStore(),
      ),
    );
    await service.myWords();
    await service.myWords();
    expect(reads, 2);
    expect(service.cachedPage('my-words', {'page': '1', 'search': ''}), isNull);
  });
}
