import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/api/api_config.dart';
import 'package:sign_voice/services/media/sign_video_source.dart';
import 'package:sign_voice/services/notifications/notification_service.dart';
import 'package:sign_voice/services/sign_ai/speech_output.dart';
import 'package:sign_voice/services/sign_ai/local_hand_tracker_native.dart';
import 'package:sign_voice/services/user/avatar_image_cache.dart';
import 'package:sign_voice/services/user/user_data_service.dart';
import 'package:sign_voice/widgets/sign_video_surface.dart';

const owner = '000000000000000000001234';

class PreflightUserData extends UserDataService {
  @override
  Future<UserBootstrap> bootstrap() async => const UserBootstrap(
    profile: {
      'displayName': 'Preflight',
      'email': '',
      'avatarUrl': '',
      'accountType': 'LOCAL',
    },
    settings: {},
    conversations: {'items': [], 'pages': 1},
    favorites: [],
  );
  @override
  Future<void> registerNotificationDevice(
    String token,
    String platform,
  ) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final report = <String, dynamic>{};

  testWidgets(
    'native hand detector initializes and returns a measured preview',
    (tester) async {
      final tracker = NativeHandTracker();
      try {
        final watch = Stopwatch()..start();
        expect(
          await tracker.initialize(),
          isTrue,
          reason: 'Run this preflight in release mode too: R8 can break MediaPipe protobuf reflection.',
        );
        report['hand_init_ms'] = watch.elapsedMilliseconds;
        final pixels = Uint8List(320 * 240 * 4);
        for (var i = 0; i < pixels.length; i += 4) {
          pixels[i] = pixels[i + 1] = pixels[i + 2] = 80;
          pixels[i + 3] = 255;
        }
        final preview = tracker.observations.first.timeout(
          const Duration(seconds: 20),
        );
        tracker.submit({
          'width': 320,
          'height': 240,
          'rotation': 0,
          'timestamp_ms': 100,
          'format': 'bgra8888',
          'encode_frame': false,
          'planes': [
            {'bytes': pixels, 'row_stride': 320 * 4, 'pixel_stride': 4},
          ],
        });
        final observation = await preview;
        expect(observation.captureSource, isIn(['android_gpu', 'android_cpu']));
        expect(observation.processingMs, greaterThan(0));
        report['hand_processing_ms'] = observation.processingMs;
        report['hand_source'] = observation.captureSource;
      } finally {
        await tracker.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets('native video plays from cached file through Conveyor', (
    tester,
  ) async {
    final response = await http
        .get(Uri.parse('${ApiConfig.baseUrl}/dictionary/popular?limit=1'))
        .timeout(const Duration(seconds: 30));
    expect(response.statusCode, 200);
    final item = (jsonDecode(response.body)['data'] as List).first as Map;
    final watch = Stopwatch()..start();
    final source = await openSignVideo(item['videoUrl'] as String);
    expect(
      source.uri.scheme,
      'file',
      reason: 'Generated clips must use the downloaded native file.',
    );
    final player = source.createController();
    try {
      await player.initialize().timeout(const Duration(seconds: 25));
      await player.setVolume(0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 240,
              child: SignVideoSurface(player),
            ),
          ),
        ),
      );
      await player.play();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(player.value.isInitialized, isTrue);
      expect(player.value.hasError, isFalse);
      expect((await player.position)!.inMilliseconds, greaterThan(0));
      report['video_cold_ms'] = watch.elapsedMilliseconds;
      watch.reset();
      final reopened = await openSignVideo(item['videoUrl'] as String);
      expect(reopened.uri, source.uri);
      report['video_cached_open_ms'] = watch.elapsedMilliseconds;
      reopened.dispose();
    } finally {
      await player.dispose();
      source.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets(
    'owned avatar persists through the real Android preferences plugin',
    (tester) async {
      final image = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7X8AAAAASUVORK5CYII=',
      );
      final url = '/user-media/avatars/$owner/${'a' * 64}.png';
      final original = AvatarImageCache()..bind(owner);
      await original.seed(owner, url, image);
      var gets = 0;
      final reopened = AvatarImageCache(
        client: MockClient((_) async {
          gets++;
          throw StateError('Unexpected network');
        }),
      )..bind(owner);
      expect(await reopened.load(owner, url), orderedEquals(image));
      expect(gets, 0);
      await reopened.clear();
      report['avatar_disk_cache_verified'] = true;
    },
  );

  testWidgets('Android actually delivers the scheduled one-minute reminder', (
    tester,
  ) async {
    final state = AppState(service: PreflightUserData())
      ..bindAccount(owner, asGuest: false);
    final device = NotificationService(state, onOpen: (_) {});
    try {
      await state.synchronize();
      await device.initialize();
      expect(
        device.permissionGranted,
        isTrue,
        reason: 'Grant POST_NOTIFICATIONS on the isolated emulator before the test.',
      );
      expect(
        device.exact,
        isTrue,
        reason: 'Allow exact alarms on the isolated emulator before the test.',
      );
      await device.testScheduledReminder();
      final local = FlutterLocalNotificationsPlugin();
      expect(
        (await local.pendingNotificationRequests()).any(
          (item) => item.id == 7098,
        ),
        isTrue,
      );
      await Future<void>.delayed(const Duration(seconds: 70));
      final active = await local.getActiveNotifications();
      expect(
        active.any((item) => item.id == 7098),
        isTrue,
        reason: 'Scheduling alone is insufficient; the notification must be posted by Android.',
      );
      await local.cancel(id: 7098);
      report['scheduled_reminder_delivered'] = true;
      report['device_timezone'] = device.timezone;
    } finally {
      device.dispose();
      state.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('native TTS can recheck installed voice data without speaking', (
    tester,
  ) async {
    final output = SpeechOutput();
    try {
      report['emulator_vietnamese_available'] = await output
          .refreshVietnameseVoice()
          .timeout(const Duration(seconds: 25));
    } finally {
      await output.stop();
    }
    binding.reportData = report;
    // No account, registration token or password is emitted.
    debugPrint('PREFLIGHT_ANDROID: ${jsonEncode(report)}');
  });
}
