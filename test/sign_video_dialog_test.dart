import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:sign_voice/features/speech/sign_sequence_panel.dart';

class FakeSignPlayer extends VideoPlayerPlatform {
  int nextId = 0;
  final streams = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  final playing = <int>[];
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      ++nextId;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final stream = StreamController<VideoEvent>();
    streams[playerId] = stream;
    scheduleMicrotask(
      () => stream.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 2),
          size: const Size(1080, 1920),
        ),
      ),
    );
    return stream.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    await streams[playerId]?.close();
  }

  @override
  Future<void> play(int playerId) async {
    playing.add(playerId);
  }

  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}

void main() {
  testWidgets(
    'sequence stops at missing words and disposes each video on mobile layout',
    (tester) async {
      final old = VideoPlayerPlatform.instance;
      final fake = FakeSignPlayer();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() => VideoPlayerPlatform.instance = old);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const SignVideoDialog(
                    initialIndex: 0,
                    playSequence: true,
                    items: [
                      {
                        'type': 'sign',
                        'text': 'chào',
                        'videoUrl': 'https://example.org/chao.mp4',
                      },
                      {'type': 'missing', 'text': 'là'},
                      {
                        'type': 'sign',
                        'text': 'bạn',
                        'videoUrl': 'https://example.org/ban.mp4',
                      },
                    ],
                  ),
                ),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(fake.playing, contains(1));
      expect(tester.takeException(), isNull);
      fake.streams[1]!.add(VideoEvent(eventType: VideoEventType.completed));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('2/3: là'), findsOneWidget);
      expect(fake.disposed, contains(1));
      expect(fake.nextId, 1);
      await tester.tap(find.text('Tiếp'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        fake.playing,
        contains(2),
        reason:
            'created=${fake.nextId}; disposed=${fake.disposed}; texts=${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}',
      );
      await tester.tap(find.text('Đóng'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(fake.disposed, contains(2));
      expect(tester.takeException(), isNull);
    },
  );
}
