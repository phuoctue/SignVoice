import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/services/sign_ai/local_hand_tracker_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('test/signvoice/hands');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
  });

  test('native bridge bounds pending frames and emits preview before a JPEG exists', () async {
    final events = StreamController<dynamic>.broadcast();
    final calls = <int>[];
    final gate = Completer<bool>();
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'initialize') return {'ready': true};
      if (call.method == 'frame') {
        calls.add((call.arguments as Map)['timestamp_ms'] as int);
        return calls.length == 1 ? gate.future : true;
      }
      return null;
    });
    final tracker = NativeHandTracker(methods: methods, events: events.stream);
    final observed = <dynamic>[];
    final frames = <dynamic>[];
    tracker.observations.listen(observed.add);
    tracker.frames.listen(frames.add);
    expect(await tracker.initialize(), isTrue);
    for (var i = 0; i < 8; i++) {
      tracker.submit({'timestamp_ms': i});
    }
    await Future<void>.delayed(Duration.zero);
    events.add({
      'type': 'preview',
      'landmarks': [],
      'fps': 30,
      'processing_ms': 12,
      'capture_source': 'android_gpu',
      'hand_observation': {'timestamp_ms': 0, 'landmarks': [], 'handedness': []},
    });
    await Future<void>.delayed(Duration.zero);
    expect(observed, hasLength(1));
    expect(observed.single.handObservation['timestamp_ms'], 0);
    expect(frames, isEmpty);
    expect(calls, [0]);
    gate.complete(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(calls, [0, 7]);
    events.add({
      'type': 'frame',
      'jpeg': Uint8List.fromList([1, 2]),
      'metadata': {
        'format': 'jpeg',
        'width': 480,
        'height': 640,
        'rotation': 0,
        'timestamp_ms': 7,
        'hand_observation': {'timestamp_ms': 7},
      },
    });
    await Future<void>.delayed(Duration.zero);
    expect(frames.single.timestampMs, 7);
    expect(frames.single.metadata['hand_observation']['timestamp_ms'], 7);
    await tracker.close();
    await events.close();
  });
  test(
    'capture credit waits for measured preview, not the fast method ACK',
    () async {
      final events = StreamController<dynamic>.broadcast();
      messenger.setMockMethodCallHandler(
        methods,
        (call) async => call.method == 'initialize' ? {'ready': true} : true,
      );
      final tracker = NativeHandTracker(
        methods: methods,
        events: events.stream,
      );
      await tracker.initialize();
      expect(tracker.canAcceptFrame, isTrue);
      tracker.submit({'timestamp_ms': 20});
      await Future<void>.delayed(Duration.zero);
      expect(tracker.canAcceptFrame, isFalse);
      void preview(int stamp) => events.add({
        'type': 'preview',
        'timestamp': stamp,
        'landmarks': [],
        'fps': 5,
        'processing_ms': 200,
        'capture_source': 'android_cpu',
      });
      preview(10);
      await Future<void>.delayed(Duration.zero);
      expect(tracker.canAcceptFrame, isFalse);
      preview(20);
      await Future<void>.delayed(Duration.zero);
      expect(tracker.canAcceptFrame, isTrue);
      await tracker.close();
      await events.close();
    },
  );
  test(
    'detector failure explicitly falls back rather than leaving a dead queue',
    () async {
      final events = StreamController<dynamic>.broadcast();
      messenger.setMockMethodCallHandler(
        methods,
        (call) async => call.method == 'initialize' ? {'ready': true} : false,
      );
      final tracker = NativeHandTracker(
        methods: methods,
        events: events.stream,
      );
      final observed = <dynamic>[];
      tracker.observations.listen(observed.add);
      await tracker.initialize();
      tracker.submit({'timestamp_ms': 1});
      await Future<void>.delayed(Duration.zero);
      expect(tracker.ready, isFalse);
      expect(observed.single.captureSource, 'unavailable');
      await tracker.close();
      await events.close();
    },
  );
}
