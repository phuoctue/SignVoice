import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/features/recognition/live_camera_screen.dart';
import 'package:sign_voice/services/sign_ai/camera_types.dart';
import 'package:sign_voice/services/sign_ai/sign_ai_config.dart';

void main() {
  test('frame transport preserves timestamp, rotation and plane bytes', () {
    final frame = CapturedFrame(
      {'format': 'yuv420', 'width': 32, 'height': 24, 'rotation': 270},
      [
        Uint8List.fromList([5, 6, 7]),
      ],
    );
    final packet = frame.packet(9, 1723);
    final length = ByteData.sublistView(packet).getUint32(0, Endian.big);
    final header = jsonDecode(
      utf8.decode(packet.sublist(4, 4 + length)),
    ) as Map<String, dynamic>;
    expect(header['sequence'], 9);
    expect(header['timestamp_ms'], 1723);
    expect(header['rotation'], 270);
    expect(header['mirrored'], false);
    expect(packet.sublist(4 + length), [5, 6, 7]);
  });
  test(
    'AI URL rejects the Flutter origin but accepts a separate service/proxy',
    () {
      final app = Uri.parse('http://localhost:8080/#S10');
      for (final url in ['http://localhost:8080', 'http://127.0.0.1:8080/']) {
        expect(
          () => SignAiConfig.socketUri(url, appUri: app),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'actionable port explanation',
              contains('8001'),
            ),
          ),
        );
      }
      expect(
        SignAiConfig.socketUri('http://localhost:8001', appUri: app).port,
        8001,
      );
      expect(
        SignAiConfig.socketUri(
          'http://localhost:8080/sign-ai',
          appUri: app,
        ).path,
        '/sign-ai/v1/stream',
      );
      expect(
        () => SignAiConfig.socketUri(
          'http://ai.example.com',
          appUri: Uri.parse('https://app.example.com'),
        ),
        throwsFormatException,
      );
    },
  );
  test('HTTPS AI service uses WSS and rejects malformed URLs', () {
    expect(
      SignAiConfig.socketUri('https://ai.example.com/sign-ai').toString(),
      'wss://ai.example.com/sign-ai/v1/stream',
    );
    expect(
      () => SignAiConfig.socketUri('file:///tmp/ai'),
      throwsFormatException,
    );
    expect(
      () => SignAiConfig.socketUri('http://localhost:8001?token=abc'),
      throwsFormatException,
    );
  });
  test(
    'public AI proxy follows the actual HTTPS origin including its port',
    () {
      final app = Uri.parse('https://phone.conveyor.cloud:443/#/recognition');
      expect(
        SignAiConfig.socketUri('/sign-ai', appUri: app).toString(),
        'wss://phone.conveyor.cloud/sign-ai/v1/stream',
      );
      expect(
        () =>
            SignAiConfig.socketUri('//untrusted.example/sign-ai', appUri: app),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'camera screen waits for user action and contains no fake result',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: LiveCameraScreen()));
      await tester.pump();
      expect(find.text('Cho phép camera'), findsOneWidget);
      expect(find.text('Cho phép sử dụng camera'), findsOneWidget);
      expect(find.text('Để sau'), findsOneWidget);
      expect(find.byTooltip('Đổi camera'), findsNothing);
      expect(find.text('Nhận diện ký hiệu'), findsOneWidget);
      expect(find.textContaining('Đang xét:'), findsNothing);
      await tester.tap(find.byTooltip('Cài đặt nhận diện'));
      await tester.pumpAndSettle();
      expect(find.text('Đối chiếu ảnh bằng LM Studio'), findsNothing);
      expect(find.text('Hiện phân tích OpenCV'), findsOneWidget);
      expect(find.textContaining('Demo thành công'), findsNothing);
      expect(find.textContaining('Đã nhận:'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  test('capture timestamp is preserved before asynchronous JPEG encoding', () {
    final frame = CapturedFrame(
      {'format': 'jpeg'},
      [Uint8List(0)],
      timestampMs: 123,
    );
    final packet = frame.packet(1, 456);
    final length = ByteData.sublistView(packet).getUint32(0, Endian.big);
    final header =
        jsonDecode(utf8.decode(packet.sublist(4, 4 + length))) as Map;
    expect(header['timestamp_ms'], 123);
  });
  for (final state in ['waiting', 'confirmed', 'unclear']) {
    testWidgets('single result panel: $state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecognitionResultCard(
              label: state == 'confirmed' ? 'rau' : null,
              waiting: 'Đang đối chiếu ký hiệu…',
              detail: 'Đưa một hoặc hai tay vào khung hình',
              unclear: state == 'unclear',
              vision: true,
            ),
          ),
        ),
      );
      expect(
        find.text('rau'),
        state == 'confirmed' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Chưa nhận diện rõ'),
        state == 'unclear' ? findsOneWidget : findsNothing,
      );
      expect(find.textContaining('%'), findsNothing);
    });
  }
  test('OpenCV overlay uses the same front/back geometry as the preview', () {
    final front = OpenCvOverlayPainter({}, mirror: true);
    final back = OpenCvOverlayPainter({}, mirror: false);
    expect(front.point([.2, .3], const Size(200, 100)), const Offset(160, 30));
    expect(back.point([.2, .3], const Size(200, 100)), const Offset(40, 30));
  });
}
