import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/services/sign_ai/stream_timing.dart';
import 'package:sign_voice/services/sign_ai/video_frame_gate.dart';

void main() {
  test('only fresh decoded frames enter encoding while transport is ready', () {
    final gate = VideoFrameGate();
    expect(gate.claim(0, 0, ready: false), isFalse);
    expect(gate.claim(0, 0, ready: true), isTrue);
    expect(gate.claim(0, 100, ready: true), isFalse);
    expect(gate.claim(.1, 100, ready: true), isTrue);
    expect(gate.claim(.12, 120, ready: true), isFalse);
    expect(gate.claim(.12, 134, ready: true), isTrue);
    expect(gate.claim(double.nan, 200, ready: true), isFalse);
  });

  test('30 FPS callback jitter does not halve the capture rate', () {
    final gate = VideoFrameGate();
    for (var frame = 0; frame < 90; frame++) {
      final time = (frame * 1000 / 30).round();
      expect(gate.claim(frame / 30, time, ready: true), isTrue);
    }
  });

  test('timing follows processed sequences when intermediate frames drop', () {
    final timing = StreamTiming();
    timing.sent(0, 100, encodingMs: 4);
    timing.sent(1, 140, encodingMs: 6);
    timing.sent(2, 180, encodingMs: 8);
    timing.received(0, 200);
    expect(timing.resultMs, 100);
    timing.received(2, 270);
    expect(timing.resultMs, 90);
    timing.received(
      1,
      280,
    ); // Dropped/stale result cannot change current timing.
    expect(timing.resultMs, 90);
    expect(timing.sendFps, 25);
    expect(timing.encodeMs, 8);
    timing.sent(3, 5000);
    expect(timing.sendFps, 0);
  });
}
