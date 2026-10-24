import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/recognition/live_camera_screen.dart';
import 'package:sign_voice/features/recognition/recognition_screens.dart';
import 'package:sign_voice/features/speech/speech_screens.dart';
import 'package:sign_voice/services/sign_ai/camera_types.dart';
import 'package:sign_voice/services/sign_ai/media_access_error.dart';
import 'package:sign_voice/services/sign_ai/speech_input.dart';

class FakeCamera implements SignCamera {
  FakeCamera(this.initializeAction);
  final Future<void> Function() initializeAction;
  bool closed = false;
  @override
  bool get front => true;
  @override
  double get aspectRatio => 4 / 3;
  @override
  Future<void> initialize() => initializeAction();
  @override
  Widget preview() => const Text('Live camera preview');
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

class FakeSpeech extends SpeechInput {
  FakeSpeech({this.grant = false});
  final bool grant;
  int requests = 0;
  @override
  bool busy = false;
  @override
  bool listening = false;
  @override
  bool permissionGranted = false;
  @override
  String text = '';
  @override
  String? error;
  @override
  Future<void> start() async {
    requests++;
    permissionGranted = grant;
    listening = grant;
    error = grant ? null : 'Microphone đang bị chặn';
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    listening = false;
    notifyListeners();
  }

  @override
  Future<void> cancel() async {
    listening = false;
    notifyListeners();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('manual text can reach signs without requesting microphone', (
    tester,
  ) async {
    final state = AppState();
    final input = FakeSpeech();
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          home: PermissionScreen(camera: false, input: input),
          routes: {'S18': (_) => const Text('Text signs result')},
        ),
      ),
    );
    await tester.tap(find.text('Nhập văn bản để xem ký hiệu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Xin chào, tôi là An');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(state.transcript, 'Xin chào, tôi là An');
    expect(find.text('Text signs result'), findsOneWidget);
    expect(input.requests, 0);
    expect(state.microphoneAllowed, isFalse);
  });
  testWidgets(
    'cached grants do not bypass the consent page; defer opens no device',
    (tester) async {
      final state = AppState()..cameraAllowed = true;
      var requests = 0;
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            home: LiveCameraScreen(
              cameraFactory: ({required front}) {
                requests++;
                return FakeCamera(() async {});
              },
            ),
            routes: {'S08': (_) => const Text('Home after defer')},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Cho phép sử dụng camera'), findsOneWidget);
      expect(requests, 0);
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();
      expect(find.text('Home after defer'), findsOneWidget);
      expect(requests, 0);
    },
  );
  testWidgets('direct microphone route requires consent despite cached grant', (
    tester,
  ) async {
    final input = FakeSpeech(grant: true)..permissionGranted = true;
    final state = AppState()..microphoneAllowed = true;
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(home: SpeechCaptureScreen(input: input)),
      ),
    );
    expect(find.text('Cho phép sử dụng microphone'), findsOneWidget);
    expect(input.requests, 0);
    await tester.tap(find.text('Cho phép microphone'));
    await tester.pump();
    expect(input.requests, 1);
    expect(find.text('Đang lắng nghe…'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets(
    'camera permission is requested before AI; offline AI preserves preview',
    (tester) async {
      final order = <String>[];
      final state = AppState();
      final camera = FakeCamera(() async {
        order.add('camera permission');
      });
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            home: LiveCameraScreen(
              cameraFactory: ({required front}) => camera,
              ticketLoader: () async => 'test-ticket',
              channelFactory: (_) {
                order.add('AI connection');
                throw StateError('offline');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(order, isEmpty);
      await tester.tap(find.text('Cho phép camera'));
      await tester.pumpAndSettle();
      expect(order, ['camera permission', 'AI connection']);
      expect(state.cameraAllowed, isTrue);
      expect(camera.closed, isFalse);
      expect(find.text('Live camera preview'), findsOneWidget);
      expect(find.text('Chưa kết nối AI'), findsNWidgets(2));
      expect(find.text('Không thấy tay'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(camera.closed, isTrue);
    },
  );

  testWidgets(
    'denied camera permission never attempts AI or claims recognition failure',
    (tester) async {
      var connections = 0;
      final camera = FakeCamera(() async {
        throw mediaAccessError('NotAllowedError');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: LiveCameraScreen(
            cameraFactory: ({required front}) => camera,
            channelFactory: (_) {
              connections++;
              throw StateError('unexpected');
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Cho phép camera'));
      await tester.pumpAndSettle();
      expect(connections, 0);
      expect(find.text('Hướng dẫn cấp quyền'), findsOneWidget);
      expect(find.text('Chưa mở được camera'), findsNWidgets(2));
      expect(find.text('Chưa nhận diện rõ'), findsNothing);
      expect(camera.closed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'microphone grant screen requests engine permission and preserves denial',
    (tester) async {
      final input = FakeSpeech(), state = AppState();
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            home: PermissionScreen(camera: false, input: input),
          ),
        ),
      );
      expect(input.requests, 0);
      expect(state.microphoneAllowed, isFalse);
      await tester.tap(find.text('Cho phép microphone'));
      await tester.pumpAndSettle();
      expect(input.requests, 1);
      expect(state.microphoneAllowed, isFalse);
      expect(find.text('Microphone đang bị chặn'), findsOneWidget);
      expect(find.textContaining('mô phỏng quyền'), findsNothing);
    },
  );

  testWidgets(
    'speech capture shows real engine text and never inserts the old demo sentence',
    (tester) async {
      final input = FakeSpeech(grant: true), state = AppState();
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            home: SpeechCaptureScreen(input: input),
            routes: {'S18': (_) => Text(state.transcript)},
          ),
        ),
      );
      expect(input.requests, 0);
      expect(state.transcript, isEmpty);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Cho phép microphone'),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(input.requests, 1);
      expect(state.microphoneAllowed, isTrue);
      input.text = 'Tôi muốn uống nước';
      await input.stop();
      await tester.pumpAndSettle();
      expect(find.text(input.text), findsOneWidget);
      expect(find.textContaining('Xin chào, tôi có thể giúp gì'), findsNothing);
      await tester.ensureVisible(find.text('Xem văn bản'));
      await tester.tap(find.text('Xem văn bản'));
      await tester.pumpAndSettle();
      expect(state.transcript, 'Tôi muốn uống nước');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test(
    'permission errors distinguish blocked, insecure context and busy device',
    () {
      expect(
        mediaAccessError('NotAllowedError').message,
        contains('Cài đặt trang web'),
      );
      expect(mediaAccessError('insecure').message, contains('HTTPS'));
      expect(
        mediaAccessError('NotReadableError').message,
        contains('ứng dụng khác'),
      );
      expect(
        mediaAccessError('NotFoundError', device: 'microphone').message,
        contains('Không tìm thấy microphone'),
      );
    },
  );
}
