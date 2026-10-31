import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:sign_voice/features/speech/sign_sequence_panel.dart';
import 'package:sign_voice/services/media/video_source.dart';
import 'package:sign_voice/services/api/api_client.dart';

class FakeSignPlayer extends VideoPlayerPlatform {
  int nextId = 0;
  final streams = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  final playing = <int>[];
  final openedUrls = <String>[];
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    openedUrls.add(options.dataSource.uri!);
    return ++nextId;
  }

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
    'replacing the media package stops an open player and asks to reopen current media',
    (tester) async {
      final old = VideoPlayerPlatform.instance, fake = FakeSignPlayer();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() => VideoPlayerPlatform.instance = old);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SignVideoDialog(
              initialIndex: 0,
              items: const [
                {
                  'type': 'sign',
                  'text': 'mẫu',
                  'videoUrl': 'https://example.org/sample.mp4',
                },
              ],
              videoLoader: (url) async => VideoSource(Uri.parse(url)),
              prefetch: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.openedUrls, hasLength(1));
      ApiClient.instance.libraryChanged.value++;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(find.text('Ký hiệu vừa được cập nhật'), findsOneWidget);
      expect(fake.disposed, contains(1));
      expect(find.text('Tiếp'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'fast navigation releases a late old clip without replacing the current player',
    (tester) async {
      final old = VideoPlayerPlatform.instance;
      final fake = FakeSignPlayer();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() => VideoPlayerPlatform.instance = old);
      final late = Completer<VideoSource>();
      var released = 0;
      final prefetched = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SignVideoDialog(
                    initialIndex: 0,
                    videoLoader: (url) async => url.endsWith('one.mp4')
                        ? late.future
                        : VideoSource(Uri.parse(url)),
                    prefetch: (url) async {
                      prefetched.add(url);
                    },
                    items: const [
                      {
                        'type': 'sign',
                        'text': 'một',
                        'videoUrl': 'https://example.org/one.mp4',
                      },
                      {
                        'type': 'sign',
                        'text': 'hai',
                        'videoUrl': 'https://example.org/two.mp4',
                      },
                      {
                        'type': 'sign',
                        'text': 'ba',
                        'videoUrl': 'https://example.org/three.mp4',
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
      expect(find.text('Đang tải video…'), findsOneWidget);
      expect(prefetched, [
        'https://example.org/two.mp4',
        'https://example.org/three.mp4',
      ]);
      await tester.tap(find.text('Tiếp'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      late.complete(
        VideoSource(Uri.parse('https://example.org/one.mp4'), () => released++),
      );
      await tester.pump();
      expect(released, 1);
      expect(fake.openedUrls, ['https://example.org/two.mp4']);
      expect(find.text('2/3: hai'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(fake.disposed, [1]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('word playback after spelling opens the selected word', (
    tester,
  ) async {
    final old = VideoPlayerPlatform.instance;
    final fake = FakeSignPlayer();
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = old);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SignSequencePanel(
              text: 'là bạn',
              loader: (_) async => {
                'segments': [
                  {
                    'type': 'fingerspelling',
                    'text': 'là',
                    'letters': [
                      {
                        'type': 'sign',
                        'text': 'l',
                        'word': 'l',
                        'videoUrl': 'https://example.org/l.mp4',
                      },
                      {
                        'type': 'sign',
                        'text': 'à',
                        'word': 'a',
                        'videoUrl': 'https://example.org/a.mp4',
                      },
                    ],
                  },
                  {
                    'type': 'sign',
                    'text': 'bạn',
                    'word': 'bạn',
                    'videoUrl': 'https://example.org/ban.mp4',
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Xem ký hiệu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Xem động tác'));
    await tester.tap(find.text('Xem động tác'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(fake.openedUrls, ['https://example.org/ban.mp4']);
    expect(find.text('3/3: bạn'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
  });

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
