import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/services/api/api_client.dart';

import 'auth_fixtures.dart';

void main() {
  test('video upload streams the file with a known content length', () async {
    final bytes = [1, 2, 3, 4, 255];
    var reads = 0;
    final api = ApiClient(
      tokenStorage: MemoryTokenStore()..accessToken = 'editor',
      useRefreshCookie: false,
      client: MockClient((request) async {
        expect(request.contentLength, bytes.length);
        expect(request.headers['Content-Type'], 'application/octet-stream');
        expect(request.headers['Authorization'], 'Bearer editor');
        expect(request.bodyBytes, bytes);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'videoUrl': 'http://localhost:3000/sign-media/converted.mp4',
            },
          }),
          201,
        );
      }),
    );
    addTearDown(api.dispose);
    final result = await AdminWorkspaceService(apiClient: api)
        .uploadVideoStream(() {
          reads++;
          return Stream.fromIterable([bytes.sublist(0, 2), bytes.sublist(2)]);
        }, bytes.length);
    expect(reads, 1);
    expect(result, endsWith('/converted.mp4'));
  });

  test(
    'video upload sends binary data with the existing authenticated client',
    () async {
      final bytes = [0, 0, 0, 24, ...utf8.encode('ftypmp42'), 0, 1, 2, 255];
      final store = MemoryTokenStore()..accessToken = 'editor-access';
      final api = ApiClient(
        tokenStorage: store,
        useRefreshCookie: false,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/dictionary/video-upload');
          expect(request.method, 'POST');
          expect(request.headers['Content-Type'], 'application/octet-stream');
          expect(request.headers['Authorization'], 'Bearer editor-access');
          expect(request.bodyBytes, bytes);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'videoUrl': 'http://localhost:3000/sign-media/video.mp4',
              },
            }),
            201,
          );
        }),
      );
      addTearDown(api.dispose);
      expect(
        await AdminWorkspaceService(apiClient: api).uploadVideo(bytes),
        'http://localhost:3000/sign-media/video.mp4',
      );
    },
  );
}
