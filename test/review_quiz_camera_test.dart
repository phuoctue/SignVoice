import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/features/learning/review_quiz_screen.dart';
import 'package:sign_voice/features/learning/quiz_camera_connection.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/services/sign_ai/camera_capture.dart';
import 'package:sign_voice/services/sign_ai/media_access_error.dart';

class QuizService extends LearningService {
  @override
  Future<LearningRecord> quiz(String id) async => {
    '_id': id,
    'questions': [
      {'entryId': 'word', 'word': 'ai', 'prompt': 'Làm ký hiệu ai'},
    ],
  };
}

class DelayedCamera implements SignCamera {
  final initialization = Completer<void>();
  bool initialized = false, closed = false;
  @override
  bool get front => true;
  @override
  double get aspectRatio => 4 / 3;
  @override
  Future<void> initialize() async {
    await initialization.future;
    initialized = true;
  }

  @override
  Widget preview() {
    if (!initialized) {
      throw StateError('Preview was requested before initialization');
    }
    return const Text('Camera preview ready');
  }

  @override
  Future<void> start(
    void Function(CapturedFrame) onFrame,
    bool Function() ready,
  ) async {}
  @override
  Future<void> close() async {
    closed = true;
  }
}

class StreamingQuizCamera extends DelayedCamera
    implements LocalTrackingCamera, ForegroundTrackingCamera {
  final observations = StreamController<LocalHandObservation>.broadcast();
  int contexts = 0;
  @override
  Stream<LocalHandObservation> get localTracking => observations.stream;
  @override
  void updateTrackingContext(List<dynamic> anchor, int timestampMs) =>
      contexts++;
}

class QuizChannel implements WebSocketChannel {
  final events = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  late final QuizSink output = QuizSink(this);
  void reply(Map<String, dynamic> data) => events.add(jsonEncode(data));
  @override
  WebSocketSink get sink => output;
  @override
  Stream<dynamic> get stream => events.stream;
  @override
  Future<void> get ready async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class QuizSink implements WebSocketSink {
  QuizSink(this.channel);
  final QuizChannel channel;
  @override
  void add(dynamic data) {
    if (data is! String) return;
    final message = jsonDecode(data) as Map<String, dynamic>;
    channel.sent.add(message);
    if (message.containsKey('mode')) {
      channel.reply({
        'type': 'ready',
        'stream_protocol': 2,
        'live_word_observations': true,
      });
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await channel.events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> mount(
  WidgetTester tester,
  DelayedCamera camera,
  Future<String> Function() ticket,
) async {
  await tester.pumpWidget(
    Provider<LearningService>.value(
      value: QuizService(),
      child: MaterialApp(
        home: ReviewQuizScreen(
          quizId: 'quiz',
          cameraFactory: ({required bool front}) => camera,
          ticketLoader: ticket,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Mở camera nhận diện'));
  await tester.tap(find.text('Mở camera nhận diện'));
  await tester.pump();
}

void main() {
  testWidgets(
    'quiz forwards measured hands and keeps confirmed feedback until retry',
    (tester) async {
      final camera = StreamingQuizCamera()..initialization.complete();
      final socket = QuizChannel();
      final retrySocket = QuizChannel();
      var connections = 0;
      await tester.pumpWidget(
        Provider<LearningService>.value(
          value: QuizService(),
          child: MaterialApp(
            home: ReviewQuizScreen(
              quizId: 'quiz',
              cameraFactory: ({required bool front}) => camera,
              ticketLoader: () async => 'ticket',
              channelFactory: (_) => connections++ == 0 ? socket : retrySocket,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mở camera nhận diện'));
      await tester.tap(find.text('Mở camera nhận diện'));
      await tester.pumpAndSettle();
      camera.observations.add(
        const LocalHandObservation(
          [],
          30,
          5,
          handObservation: {'timestamp_ms': 1000},
        ),
      );
      await tester.pump();
      expect(
        socket.sent.where((m) => m['type'] == 'hand_observation').length,
        1,
      );
      socket.reply({
        'type': 'result',
        'hands': 1,
        'confirmed': null,
        'timestamp_ms': 1000,
        'foreground_context': [.5, .4, .2, 1],
      });
      await tester.pumpAndSettle();
      expect(camera.contexts, 1);
      expect(find.textContaining('Đã thấy 1 tay'), findsOneWidget);
      socket.reply({'type': 'result', 'hands': 1, 'confirmed': 'ai'});
      await tester.pumpAndSettle();
      expect(find.text('Đúng ký hiệu “ai”'), findsOneWidget);
      socket.reply({'type': 'result', 'hands': 0, 'confirmed': null});
      await tester.pumpAndSettle();
      expect(find.text('Đúng ký hiệu “ai”'), findsOneWidget);
      socket.events.addError(StateError('connection lost'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Đúng ký hiệu “ai”'), findsOneWidget);
      await tester.ensureVisible(find.text('Làm lại ký hiệu'));
      await tester.tap(find.text('Làm lại ký hiệu'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        connections,
        2,
        reason: 'Retry must open a fresh recognition session',
      );
      await tester.pumpAndSettle();
      retrySocket.reply({'type': 'result', 'hands': 1, 'confirmed': 'khác'});
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa khớp'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await camera.observations.close();
      await tester.pump();
    },
  );
  test(
    'public HTTPS gateway includes its authentication ticket in WSS',
    () async {
      var tickets = 0;
      final uri = await quizCameraSocketUri(
        serviceUrl: 'https://funashbox30.conveyor.cloud/sign-ai',
        gatewayUrl: 'https://funashbox30.conveyor.cloud/sign-ai',
        ticketLoader: () async {
          tickets++;
          return 'quiz-ticket';
        },
      );
      expect(uri.scheme, 'wss');
      expect(uri.path, '/sign-ai/v1/stream');
      expect(uri.queryParameters['ticket'], 'quiz-ticket');
      expect(tickets, 1);
    },
  );

  test(
    'local gateway keeps its explicit port and authentication ticket',
    () async {
      final uri = await quizCameraSocketUri(
        serviceUrl: 'http://localhost:3001/sign-ai',
        gatewayUrl: 'http://localhost:3001/sign-ai',
        ticketLoader: () async => 'local-ticket',
      );
      expect(uri.port, 3001);
      expect(uri.queryParameters['ticket'], 'local-ticket');
    },
  );

  test(
    'separate recognition service does not receive a gateway ticket',
    () async {
      final uri = await quizCameraSocketUri(
        serviceUrl: 'http://localhost:8001',
        gatewayUrl: 'http://localhost:3001/sign-ai',
        ticketLoader: () async => throw StateError('must not request ticket'),
      );
      expect(uri.path, '/v1/stream');
      expect(uri.hasQuery, isFalse);
    },
  );

  testWidgets(
    'does not render an unregistered camera preview during initialization',
    (tester) async {
      final camera = DelayedCamera();
      final ticket = Completer<String>();
      await mount(tester, camera, () => ticket.future);
      expect(tester.takeException(), isNull);
      expect(find.text('Camera preview ready'), findsNothing);
      camera.initialization.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('Camera preview ready'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      ticket.complete('ticket');
      await tester.pump();
      expect(camera.closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stop releases camera and cancels an AI connection still opening',
    (tester) async {
      final camera = DelayedCamera();
      final ticket = Completer<String>();
      await mount(tester, camera, () => ticket.future);
      camera.initialization.complete();
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.text('Dừng camera'));
      await tester.tap(find.text('Dừng camera'));
      await tester.pumpAndSettle();
      expect(camera.closed, isTrue);
      expect(find.text('Camera preview ready'), findsNothing);
      expect(find.text('Dừng camera'), findsNothing);
      expect(find.text('Mở camera nhận diện'), findsOneWidget);
      ticket.complete('late-ticket');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Thử kết nối lại'), findsNothing);
    },
  );

  testWidgets('shows permission errors after releasing the failed camera', (
    tester,
  ) async {
    final camera = DelayedCamera();
    await mount(tester, camera, () async => 'unused');
    camera.initialization.completeError(
      const MediaAccessException('Quyền camera đã bị chặn.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Quyền camera đã bị chặn.'), findsOneWidget);
    expect(find.text('Thử kết nối lại'), findsOneWidget);
    expect(camera.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'distinguishes recognition connection failure from camera permission failure',
    (tester) async {
      final camera = DelayedCamera();
      await mount(
        tester,
        camera,
        () async => throw StateError('ticket unavailable'),
      );
      camera.initialization.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Camera đã mở nhưng chưa kết nối được dịch vụ nhận diện. Hãy thử kết nối lại.',
        ),
        findsOneWidget,
      );
      expect(camera.closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
