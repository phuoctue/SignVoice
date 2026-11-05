import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import 'auth_fixtures.dart';

void main() {
  test(
    'public landing reads survive authentication changing during startup',
    () async {
      final gate = Completer<void>();
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          await gate.future;
          return http.Response(
            jsonEncode({
              'data': [],
              'pagination': {'total': 0},
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final service = AdminWorkspaceService(apiClient: api);
      final words = service.published();
      final categories = service.activeCategories();
      await Future<void>.delayed(Duration.zero);
      api.beginAuthentication();
      gate.complete();
      expect((await words).total, 0);
      expect(await categories, isEmpty);
    },
  );
  test(
    'public collections survive session change without reusing account cache',
    () async {
      final gate = Completer<void>();
      var reads = 0;
      final api = ApiClient(
        tokenStorage: MemoryTokenStore(),
        client: MockClient((request) async {
          expect(request.headers.containsKey('Authorization'), isFalse);
          reads++;
          await gate.future;
          return http.Response(
            jsonEncode({
              'data': {
                'items': [],
                'pagination': {'total': 1},
              },
            }),
            200,
          );
        }),
      );
      addTearDown(api.dispose);
      final service = LearningService(client: api);
      final response = service.collectionRead('/shared-collections');
      await Future<void>.delayed(Duration.zero);
      api.beginAuthentication();
      gate.complete();
      expect((await response)['pagination']['total'], 1);
      await service.collectionRead('/shared-collections');
      expect(reads, 2);
    },
  );
}
