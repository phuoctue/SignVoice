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

class _Channel implements WebSocketChannel {
  final events = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  final frames = <Map<String, dynamic>>[];
  late final _Sink _sink = _Sink(this);
  @override
  WebSocketSink get sink => _sink;
  @override
  Stream<dynamic> get stream => events.stream;
  @override
  Future<void> get ready async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  _Sink(this.channel);
  final _Channel channel;
  @override
  void add(dynamic data) {
    if (data is Uint8List) {
      final length = ByteData.sublistView(data).getUint32(0, Endian.big);
      channel.frames.add(
        jsonDecode(utf8.decode(data.sublist(4, 4 + length)))
            as Map<String, dynamic>,
      );
      return;
    }
    channel.sent.add(jsonDecode(data as String) as Map<String, dynamic>);
    if (channel.sent.last.containsKey('mode')) {
      channel.events.add(
        jsonEncode({
          'type': 'ready',
          'stream_protocol': 2,
          'word_classes': 144,
        }),
      );
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      channel.events.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StreamingCamera extends FakeCamera {
  _StreamingCamera() : super(() async {});
  late void Function(CapturedFrame) emit;
  late bool Function() readyToSend;
  @override
  Future<void> start(
    void Function(CapturedFrame) onFrame,
    bool Function() ready,
  ) async {
    emit = onFrame;
    readyToSend = ready;
  }
}

class _TrackedCamera extends _StreamingCamera implements LocalTrackingCamera {
  final observations = StreamController<LocalHandObservation>.broadcast();
  @override
  Stream<LocalHandObservation> get localTracking => observations.stream;
  @override
  Future<void> close() async {
    await observations.close();
    await super.close();
  }
}

void main() {
  for (final mode in ['letters', 'words']) {
    testWidgets(
      '$mode XYZ sends without JPEG and waits for its own receipt ACK',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'sign_ai_mode': mode,
          'sign_ai_vision': false,
        });
        final channel = _Channel();
        final camera = _TrackedCamera();
        await tester.pumpWidget(
          MaterialApp(
            home: LiveCameraScreen(
              cameraFactory: ({required front}) => camera,
              channelFactory: (_) => channel,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cho phép camera'));
        await tester.pumpAndSettle();
        channel.events.add(
          jsonEncode({
            'type': 'ready',
            'stream_protocol': 2,
            'live_glyph_observations': true,
            'live_word_observations': true,
          }),
        );
        await tester.pump();
        await tester.pump();
        void measured(int stamp) => camera.observations.add(
          LocalHandObservation(
            [],
            15,
            20,
            handObservation: {
              'timestamp_ms': stamp,
              'landmarks': [],
              'handedness': [],
            },
          ),
        );
        measured(1000);
        await tester.pump();
        await tester.pump();
        expect(
          channel.sent.where((m) => m['type'] == 'hand_observation').length,
          1,
        );
        expect(channel.frames, isEmpty);
        await tester.pump(const Duration(milliseconds: 120));
        measured(1120);
        await tester.pump();
        await tester.pump();
        expect(
          channel.sent.where((m) => m['type'] == 'hand_observation').length,
          1,
        );
        channel.events.add(
          jsonEncode({'type': 'observation_received', 'timestamp_ms': 1000}),
        );
        await tester.pump();
        await tester.pump();
        expect(channel.sent.last['observation']['timestamp_ms'], 1120);
        measured(1140);
        await tester.pump();
        await tester.pump();
        expect(
          channel.sent.where((m) => m['type'] == 'hand_observation').length,
          2,
        );
        expect(channel.frames, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
  testWidgets('local tracking paints promptly but cannot confirm a word', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'sign_ai_mode': 'words',
      'sign_ai_vision': false,
    });
    final channel = _Channel();
    final camera = _TrackedCamera();
    await tester.pumpWidget(
      MaterialApp(
        home: LiveCameraScreen(
          cameraFactory: ({required front}) => camera,
          channelFactory: (_) => channel,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cho phép camera'));
    await tester.pumpAndSettle();
    final hands = [
      List.generate(21, (i) => [.2 + i * .001, .3 + i * .001]),
    ];
    camera.observations.add(
      const LocalHandObservation([], 0, 0, captureSource: 'initializing'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Đang khởi tạo bộ dò tay…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Đang khởi tạo bộ dò tay…'), findsOneWidget);
    // Interim service measurements remain useful while local assets download.
    channel.events.add(
      jsonEncode({
        'type': 'result',
        'hands': 1,
        'status': 'tracking',
        'landmarks': hands,
        'events': [],
      }),
    );
    await tester.pump();
    await tester.pump();
    final interimPaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('sign-hand-landmarks')),
    );
    expect((interimPaint.painter as dynamic).hands, hands);
    expect(find.text('Đang khởi tạo bộ dò tay…'), findsOneWidget);
    camera.observations.add(
      LocalHandObservation(hands, 30, 20, initializationMs: 1400),
    );
    await tester.pump();
    await tester.pump();
    final painted = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('sign-hand-landmarks')),
    );
    expect((painted.painter as dynamic).hands, hands);
    expect(find.text('Đang khởi tạo bộ dò tay…'), findsNothing);
    expect(find.text('rau'), findsNothing);
    channel.events.add(
      jsonEncode({
        'type': 'result',
        'hands': 1,
        'confirmed': 'rau',
        'status': 'confirmed',
        'landmarks': [],
        'events': [],
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('rau'), findsOneWidget);
    // A delayed remote result cannot resurrect stale local joints.
    channel.events.add(
      jsonEncode({
        'type': 'result',
        'hands': 1,
        'status': 'tracking',
        'landmarks': hands,
        'events': [],
      }),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final stalePaint = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('sign-hand-landmarks')),
    );
    expect((stalePaint.painter as dynamic).hands, isEmpty);

    channel.events.addError(StateError('connection lost'));
    await tester.pump();
    await tester.pump();
    expect(find.text('rau'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(camera.closed, isTrue);
  });

  testWidgets('word stream waits for receipt ACK, not for LM or inference', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'sign_ai_mode': 'words',
      'sign_ai_vision': false,
    });
    final channel = _Channel();
    final camera = _StreamingCamera();
    await tester.pumpWidget(
      MaterialApp(
        home: LiveCameraScreen(
          cameraFactory: ({required front}) => camera,
          channelFactory: (_) => channel,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cho phép camera'));
    await tester.pumpAndSettle();
    expect(channel.sent.single['vision'], isFalse);
    final frame = CapturedFrame(
      {'format': 'jpeg', 'encode_ms': 5},
      [
        Uint8List.fromList([1, 2]),
      ],
      timestampMs: 123,
    );
    camera.emit(frame);
    camera.emit(frame);
    expect(channel.frames.length, 1);
    expect(channel.frames.single['timestamp_ms'], 123);
    channel.events.add(jsonEncode({'type': 'frame_received', 'sequence': 0}));
    await tester.pump();
    // No inference result has arrived, but the next fresh frame can be sent.
    expect(camera.readyToSend(), isTrue);
    camera.emit(
      CapturedFrame({'format': 'jpeg'}, frame.planes, timestampMs: 156),
    );
    expect(channel.frames.length, 2);
    channel.events.add(jsonEncode({'type': 'frame_received', 'sequence': 0}));
    await tester.pump();
    expect(camera.readyToSend(), isFalse); // An old ACK cannot release frame 1.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(camera.closed, isTrue);
  });

  for (final mode in ['digits', 'letters', 'words', 'all']) {
    testWidgets(
      '$mode handshake applies the actual review policy and displays a result',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'sign_ai_mode': mode,
          'sign_ai_vision': true,
        });
        final channel = _Channel();
        await tester.pumpWidget(
          MaterialApp(
            home: LiveCameraScreen(
              cameraFactory: ({required front}) => FakeCamera(() async {}),
              channelFactory: (_) => channel,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cho phép camera'));
        await tester.pumpAndSettle();
        expect(channel.sent.single['mode'], mode);
        expect(channel.sent.single['vision'], isFalse);
        final label = mode == 'digits'
            ? '3'
            : mode == 'letters'
            ? 'a'
            : 'rau';
        channel.events.add(
          jsonEncode({
            'type': 'result',
            'hands': 1,
            'confirmed': label,
            'status': 'confirmed',
            'vision_enabled': false,
            'events': [],
            'landmarks': [],
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        expect(find.text('Đang đối chiếu ký hiệu…'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
