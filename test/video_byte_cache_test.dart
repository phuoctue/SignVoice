import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/services/media/video_byte_cache.dart';

void main() {
  test(
    'deduplicates parallel loads and evicts bytes beyond the memory budget',
    () async {
      var calls = 0;
      final cache = VideoByteCache(
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes(Uint8List(8), 200);
        }),
        maxBytes: 12,
      );
      final a = Uri.parse('https://example.org/a.mp4'),
          b = Uri.parse('https://example.org/b.mp4');
      await Future.wait([cache.load(a), cache.load(a)]);
      expect(calls, 1);
      await cache.load(a);
      expect(calls, 1);
      await cache.load(b);
      await cache.load(a);
      expect(calls, 3);
      expect(cache.retainedBytes, lessThanOrEqualTo(12));
    },
  );
  test('failed and oversized responses are not retained', () async {
    var calls = 0;
    final cache = VideoByteCache(
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('', 503)
            : http.Response.bytes(Uint8List(20), 200);
      }),
      maxBytes: 12,
      maxFileBytes: 16,
    );
    final uri = Uri.parse('https://example.org/a.mp4');
    await expectLater(cache.load(uri), throwsStateError);
    await expectLater(cache.load(uri), throwsStateError);
    expect(calls, 2);
    expect(cache.retainedBytes, 0);
  });
}
