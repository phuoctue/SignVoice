import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:sign_voice/features/recognition/live_camera_screen.dart';
import 'package:sign_voice/services/sign_ai/camera_types.dart';

import 'media_permissions_test.dart' show FakeCamera;
import '../test_browser/tcn180_camera_main.dart' as camera_harness;

class _Channel implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];
  late final _Sink output = _Sink(this);
  @override
  WebSocketSink get sink => output;
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  Future<void> get ready async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  _Sink(this.channel);
  final _Channel channel;
  @override
  void add(dynamic value) {
    if (value is Uint8List) return;
    final message = jsonDecode(value as String) as Map<String, dynamic>;
    channel.sent.add(message);
    if (message.containsKey('mode')) {
      scheduleMicrotask(
        () => channel.incoming.add(
          jsonEncode({
            'type': 'ready',
            'stream_protocol': 2,
            'word_classes': 180,
            'live_word_observations': true,
            'worker_identity': {'word_model_sha256': 'test-checkpoint'},
          }),
        ),
      );
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    unawaited(channel.incoming.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Camera extends FakeCamera {
  _Camera() : super(() async {});
  late void Function(CapturedFrame) emit;
  @override
  Future<void> start(
    void Function(CapturedFrame) onFrame,
    bool Function() ready,
  ) async => emit = onFrame;
}

class _PixelCamera extends _Camera
    implements PixelDiagnosticCamera, LocalTrackingCamera {
  final pixelFrames = StreamController<CapturedFrame>.broadcast();
  final localEvents = StreamController<LocalHandObservation>.broadcast();
  @override
  Stream<LocalHandObservation> get localTracking => localEvents.stream;
  bool pixelsEnabled = false;
  bool? enabledAtInitialize;
  @override
  void setPixelDiagnostic(bool enabled) => pixelsEnabled = enabled;
  @override
  Stream<CapturedFrame> get diagnosticPixels => pixelFrames.stream;
  @override
  Future<void> initialize() async {
    enabledAtInitialize = pixelsEnabled;
    await super.initialize();
  }
}

void main() {
  testWidgets('PNG opt-in reaches camera and exports paired pixels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final cameras = <_PixelCamera>[];
    Map<String, dynamic>? exported;
    await tester.pumpWidget(
      MaterialApp(
        home: LiveCameraScreen(
          diagnosticsEnabled: true,
          ticketLoader: () async => 'test-stream-ticket',
          cameraFactory: ({required front}) {
            final camera = _PixelCamera();
            cameras.add(camera);
            return camera;
          },
          channelFactory: (_) => _Channel(),
          diagnosticExporter: (content) async {
            exported = jsonDecode(content) as Map<String, dynamic>;
            return 'Đã xuất';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cho phép camera'));
    await tester.pumpAndSettle();
    expect(cameras.single.enabledAtInitialize, isFalse);
    await tester.tap(find.byTooltip('Ghi chẩn đoán'));
    await tester.pumpAndSettle();
    expect(find.text('Kèm ảnh PNG'), findsOneWidget);
    await tester.tap(find.text('Kèm ảnh PNG'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(cameras.last.enabledAtInitialize, isTrue);
    final measured = <String, dynamic>{
      'timestamp_ms': 1250,
      'width': 640,
      'height': 480,
      'landmarks': <dynamic>[],
      'handedness': <dynamic>[],
    };
    cameras.last.localEvents.add(
      LocalHandObservation(
        const [],
        15,
        1,
        timestampMs: 1250,
        handObservation: measured,
      ),
    );
    cameras.last.pixelFrames.add(
      CapturedFrame(
        {
          'format': 'png',
          'width': 640,
          'height': 480,
          'timestamp_ms': 1250,
          'pixel_stage': 'resized_detector_input',
          'mirrored': false,
          'rotation': 0,
          'hand_observation': {'timestamp_ms': 1250, 'landmarks': []},
        },
        [
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        ],
        timestampMs: 1250,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chẩn đoán: 1 ảnh PNG'), findsOneWidget);
    await tester.tap(find.byTooltip('Dừng và xuất chẩn đoán'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(exported!['contains_pixels'], isTrue);
    final pixel = (exported!['pixel_capture']['frames'] as List).single as Map;
    expect(pixel['timestamp_ms'], 1250);
    expect(pixel['hand_observation']['timestamp_ms'], 1250);
    expect(pixel['pixel_stage'], 'resized_detector_input');
    expect(base64Decode(pixel['png_base64'] as String), [
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
    ]);
    expect(cameras.last.pixelsEnabled, isFalse);
    final sentObservation =
        (exported!['messages'] as List)
                .where((m) => m['kind'] == 'observation_send')
                .single
            as Map;
    expect(sentObservation['observation'], measured);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    for (final camera in cameras) {
      await camera.pixelFrames.close();
      await camera.localEvents.close();
    }
  });
  testWidgets('local harness opens camera permission without backend login', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    camera_harness.main();
    await tester.pumpAndSettle();
    expect(find.text('Cho phép camera'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('normal camera does not offer or request diagnostics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final channel = _Channel();
    await tester.pumpWidget(
      MaterialApp(
        home: LiveCameraScreen(
          ticketLoader: () async => 'test-stream-ticket',
          diagnosticsEnabled: false,
          cameraFactory: ({required front}) => _Camera(),
          channelFactory: (_) => channel,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cho phép camera'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ghi chẩn đoán'), findsNothing);
    expect(channel.sent.single.containsKey('diagnostic'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('opt-in reconnects diagnostic worker and exports bounded JSON', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final channels = <_Channel>[];
    final cameras = <_Camera>[];
    Map<String, dynamic>? exported;
    await tester.pumpWidget(
      MaterialApp(
        home: LiveCameraScreen(
          ticketLoader: () async => 'test-stream-ticket',
          diagnosticsEnabled: true,
          diagnosticExporter: (content) async {
            exported = jsonDecode(content) as Map<String, dynamic>;
            return 'Đã xuất chẩn đoán';
          },
          cameraFactory: ({required front}) {
            final camera = _Camera();
            cameras.add(camera);
            return camera;
          },
          channelFactory: (_) {
            final channel = _Channel();
            channels.add(channel);
            return channel;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cho phép camera'));
    await tester.pumpAndSettle();
    expect(channels.single.sent.single.containsKey('diagnostic'), isFalse);
    await tester.tap(find.byTooltip('Ghi chẩn đoán'));
    // Stream cancellation can complete outside the widget fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(channels, hasLength(2));
    expect(channels.last.sent.single['diagnostic'], isTrue);
    cameras.last.emit(
      CapturedFrame(
        {'format': 'jpeg', 'encode_ms': 3},
        [Uint8List(1)],
        timestampMs: 1000,
      ),
    );
    channels.last.incoming.add(
      jsonEncode({
        'type': 'result',
        'sequence': 0,
        'timestamp_ms': 1000,
        'worker_diagnostic': {
          'records': [
            {'now': 1.0, 'decision_top': 'rau'},
          ],
        },
        'events': [],
        'hands': 0,
      }),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Dừng và xuất chẩn đoán'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(exported!['contains_pixels'], isFalse);
    expect(
      exported!['worker_identity']['word_model_sha256'],
      'test-checkpoint',
    );
    final messages = exported!['messages'] as List;
    expect(
      messages.first['observation_pacing'],
      const bool.fromEnvironment('CAMERA_PHASE_PACING')
          ? 'phase_15hz_v1'
          : 'minimum_gap_66ms',
    );
    expect(
      messages.any((m) => m['kind'] == 'frame' && m['timestamp_ms'] == 1000),
      isTrue,
    );
    expect(messages.any((m) => m['worker_diagnostic'] != null), isTrue);
    expect(jsonEncode(exported).contains('"token"'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
