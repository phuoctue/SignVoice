import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';

import 'auth_fixtures.dart';

http.Response ok(dynamic value) =>
    http.Response(jsonEncode({'data': value}), 200);
void main() {
  test(
    'identical concurrent reads share transport and isolate mutable results',
    () async {
      final gate = Completer<http.Response>();
      var reads = 0;
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((_) {
          reads++;
          return gate.future;
        }),
      );
      addTearDown(api.dispose);
      final first = api.get(
        '/items',
        queryParameters: {'page': '1', 'search': 'word'},
      );
      final second = api.get(
        '/items',
        queryParameters: {'search': 'word', 'page': '1'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      gate.complete(
        ok([
          {'name': 'original'},
        ]),
      );
      final a = await first, b = await second;
      a['data'][0]['name'] = 'changed';
      expect(b['data'][0]['name'], 'original');
    },
  );

  test(
    'completed data and failures are never reused as authorization cache',
    () async {
      var reads = 0;
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((_) async {
          reads++;
          return reads == 1
              ? ok('allowed')
              : http.Response('{"error":{"message":"Forbidden"}}', 403);
        }),
      );
      addTearDown(api.dispose);
      await api.get('/admin/users');
      await expectLater(
        api.get('/admin/users'),
        throwsA(isA<ForbiddenException>()),
      );
      await expectLater(
        api.get('/admin/users'),
        throwsA(isA<ForbiddenException>()),
      );
      expect(reads, 3);
    },
  );

  test(
    'reads started before or during writes cannot be reused after the write',
    () async {
      final old = Completer<http.Response>(),
          during = Completer<http.Response>();
      final write = Completer<http.Response>();
      var reads = 0;
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((req) {
          if (req.method == 'PATCH') return write.future;
          reads++;
          return reads == 1
              ? old.future
              : reads == 2
              ? during.future
              : Future.value(ok('current'));
        }),
      );
      addTearDown(api.dispose);
      final a = api.get('/items');
      final mutation = api.patch('/items', body: {'value': 'current'});
      final b = api.get('/items');
      await Future<void>.delayed(Duration.zero);
      expect(reads, 2);
      write.complete(ok('saved'));
      await mutation;
      expect((await api.get('/items'))['data'], 'current');
      expect(reads, 3);
      old.complete(ok('old'));
      during.complete(ok('during'));
      await Future.wait([a, b]);
    },
  );

  test('a pending read cannot cross a login boundary', () async {
    final gate = Completer<http.Response>();
    var reads = 0;
    final api = ApiClient(
      tokenStorage: MemoryTokenStore(),
      client: MockClient((_) {
        reads++;
        return reads == 1 ? gate.future : Future.value(ok('new owner'));
      }),
    );
    addTearDown(api.dispose);
    final old = api.get('/users/profile');
    final rejected = expectLater(
      old,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    api.beginAuthentication();
    expect((await api.get('/users/profile'))['data'], 'new owner');
    gate.complete(ok('old owner'));
    await rejected;
    expect(reads, 2);
  });
}
