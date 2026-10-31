import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/services/sign_ai/camera_diagnostic.dart';
import 'package:sign_voice/services/sign_ai/camera_types.dart';

void main() {
  test(
    'pixels require separate consent, are bounded and never retain secrets',
    () {
      final frame = CapturedFrame(
        {
          'format': 'png',
          'width': 16,
          'height': 16,
          'timestamp_ms': 1,
          'token': 'never-retain',
        },
        [
          Uint8List.fromList([1, 2, 3]),
        ],
      );
      final log = CameraDiagnostic()..start();
      log.addPixels(frame);
      expect(log.pixels, isEmpty);
      log.start(includePixels: true);
      for (var i = 0; i < 61; i++) {
        log.addPixels(frame);
      }
    expect(log.pixels.length, 15);
      expect(log.pixelsTruncated, isTrue);
      expect(
        log.recording,
        isTrue,
      ); // Pixel bound must not stop feature journal.
      expect(jsonDecode(log.export())['contains_pixels'], isTrue);
      expect(log.export(), isNot(contains('never-retain')));
      log.recording = false;
      log.addPixels(frame);
    expect(log.pixels.length, 15);
      log.clear();
      expect(log.includePixels, isFalse);
      expect(log.pixels, isEmpty);
    },
  );
  test('disabled by default, credentials and pixels never retained', () {
    final log = CameraDiagnostic();
    log.received({'type': 'result', 'sequence': 0}, 0);
    expect(log.messages, isEmpty);
    log.start();
    log.received({
      'type': 'result',
      'sequence': 0,
      'token': 'secret',
      'jpeg': 'pixels',
      'confirmed': 'a',
    }, 10);
    expect(log.export(), isNot(contains('secret')));
    expect(log.export(), isNot(contains('jpeg')));
    log.clear();
    expect(log.messages, isEmpty);
    expect(log.recording, isFalse);
  });
  test(
    'same client clock RTT counted once, delayed updates are not new samples',
    () {
      final log = CameraDiagnostic()..start();
      log.sent(2, 100);
      log.received({
        'type': 'result',
        'sequence': 2,
        'timing': {'detector_ms': 5},
      }, 160);
      log.received({
        'type': 'result',
        'sequence': 2,
        'timing': {'detector_ms': 5},
      }, 180);
      final summary = log.summary['send_to_first_result'] as Map;
      expect(summary['samples'], 1);
      expect(summary['median_ms'], 60);
      expect(summary['p95_ms'], 60);
      expect((log.summary['service_detector'] as Map)['samples'], 1);
    },
  );
  test('detaches mutable arrays and refuses to slide after limit', () {
    final log = CameraDiagnostic()..start();
    final points = [1, 2];
    log.add({'points': points});
    points[0] = 7;
    expect(log.messages.first['points'], [1, 2]);
    for (var i = 0; i < 6001; i++) {
      log.add({'index': i});
    }
    expect(log.truncated, isTrue);
    expect(log.messages.length, 6000);
    expect(jsonDecode(log.export())['truncated'], isTrue);
  });
}
