import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/services/media/sign_video_prefetch.dart';

void main() {
  test('only one speculative GET runs and navigation replaces obsolete waiting clips', () async {
    final first = Completer<void>(), latest = Completer<void>();
    final calls = <String>[];
    final queue = SignVideoPrefetch(
      load: (url) {
        calls.add(url);
        return url == 'a' ? first.future : latest.future;
      },
    );
    queue.warm(['a', 'b', 'c']);
    expect(calls, ['a']);
    queue.warm(['d', 'e']);
    first.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['a', 'd']);
    queue.dispose();
    latest.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['a', 'd']);
  });
  test(
    'duplicate cached clips are not fetched again by the prefetcher',
    () async {
      final calls = <String>[];
      final queue = SignVideoPrefetch(
        load: (url) async {
          calls.add(url);
        },
      );
      addTearDown(queue.dispose);
      queue.warm(['a', 'a', 'b']);
      await Future<void>.delayed(Duration.zero);
      queue.warm(['a', 'b']);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['a', 'b']);
    },
  );
}
