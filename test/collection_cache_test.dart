import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/services/auth/collection_return_route.dart';

import 'auth_fixtures.dart';

http.Response reply(Object data) =>
    http.Response(jsonEncode({'data': data}), 200);
void main() {
  test(
    'community discovery and previews can be read without authentication',
    () async {
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((request) async {
          expect(request.headers.containsKey('authorization'), isFalse);
          return reply({'items': []});
        }),
      );
      addTearDown(api.dispose);
      final service = LearningService(client: api);
      await service.collectionRead('/shared-collections');
      await service.collectionRead('/shared-collections/${'a' * 32}');
    },
  );
  test('collection reads coalesce, deep-copy and invalidate after acknowledged writes or account changes', () async {
    var reads = 0;
    final gate = Completer<http.Response>();
    final api = ApiClient(
      tokenStorage: MemoryTokenStore(),
      client: MockClient((r) async {
        if (r.method != 'GET') return reply({'_id': 'new'});
        reads++;
        if (reads == 1) return gate.future;
        return reply({
          'items': [
            {'name': 'current'},
          ],
        });
      }),
    );
    addTearDown(api.dispose);
    final service = LearningService(client: api);
    final a = service.collectionRead('/sign-collections'),
        b = service.collectionRead('/sign-collections');
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
    gate.complete(
      reply({
        'items': [
          {'name': 'first'},
        ],
      }),
    );
    final first = await a, second = await b;
    first['items'][0]['name'] = 'changed';
    expect(second['items'][0]['name'], 'first');
    final cached = service.cachedCollection('/sign-collections')!;
    cached['items'][0]['name'] = 'changed';
    expect(
      (await service.collectionRead('/sign-collections'))['items'][0]['name'],
      'first',
    );
    expect(reads, 1);
    await service.createCollection('new', '');
    expect(service.cachedCollection('/sign-collections'), isNull);
    await service.collectionRead('/sign-collections');
    expect(reads, 2);
    api.beginAuthentication();
    expect(service.cachedCollection('/sign-collections'), isNull);
    await service.collectionRead('/sign-collections');
    expect(reads, 3);
  });
  test('library revision refreshes media caches without logging out or accepting a stale in-flight read', () async {
    var revision = 'one', reads = 0;
    final gate = Completer<http.Response>();
    final api = ApiClient(
      tokenStorage: MemoryTokenStore(),
      client: MockClient((r) async {
        if (r.url.path.endsWith('/library/version')) {
          expect(r.headers.containsKey('authorization'), isFalse);
          return reply({'revision': revision});
        }
        reads++;
        if (reads == 1) return gate.future;
        return reply({
          'items': [
            {'videoUrl': 'new-hash.mp4'},
          ],
        });
      }),
    );
    addTearDown(api.dispose);
    await api.refreshLibraryRevision();
    expect(api.libraryChanged.value, 0);
    await api.refreshLibraryRevision();
    expect(api.libraryChanged.value, 0);
    final epoch = api.sessionEpoch, service = LearningService(client: api);
    final pending = service.collectionRead('/sign-collections');
    final rejected = expectLater(
      pending,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'COLLECTION_CHANGED'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    revision = 'two';
    await api.refreshLibraryRevision();
    expect(api.sessionEpoch, epoch);
    expect(api.libraryChanged.value, 1);
    gate.complete(
      reply({
        'items': [
          {'videoUrl': 'old.mp4'},
        ],
      }),
    );
    await rejected;
    expect(service.cachedCollection('/sign-collections'), isNull);
    expect(
      (await service.collectionRead(
        '/sign-collections',
      ))['items'][0]['videoUrl'],
      'new-hash.mp4',
    );
    revision = 'three';
    await api.refreshLibraryRevision();
    expect(service.cachedCollection('/sign-collections'), isNull);
  });
  test('private collection replies cannot survive a session switch', () async {
    final gate = Completer<http.Response>();
    final api = ApiClient(
      tokenStorage: MemoryTokenStore(),
      client: MockClient((_) => gate.future),
    );
    addTearDown(api.dispose);
    final service = LearningService(client: api),
        pending = service.collectionRead('/sign-collections');
    final rejected = expectLater(
      pending,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    api.beginAuthentication();
    gate.complete(
      reply({
        'items': [
          {'name': 'other account'},
        ],
      }),
    );
    await rejected;
    expect(service.cachedCollection('/sign-collections'), isNull);
  });
  test('login return accepts only the shared collection route', () {
    final route = '/collections/shared/${'a' * 32}';
    expect(validCollectionReturnRoute(route), route);
    for (final value in [
      'https://other.example/',
      '//other.example',
      '/admin',
      '$route?next=admin',
      '/collections/shared/short',
    ]) {
      expect(validCollectionReturnRoute(value), isNull);
    }
  });
}
