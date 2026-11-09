import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:sign_voice/features/learning/learning_widgets.dart';
import 'package:sign_voice/widgets/sign_video_surface.dart';

import 'sign_video_dialog_test.dart' show FakeSignPlayer;

class QuizPlayer extends FakeSignPlayer {
  Completer<void>? playGate;
  @override
  Future<void> play(int playerId) async {
    await playGate?.future;
    await super.play(playerId);
  }

  final speeds = <double>[], positions = <Duration>[];
  int pauses = 0;
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    speeds.add(speed);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    positions.add(position);
  }

  @override
  Future<void> pause(int playerId) async {
    pauses++;
  }
}

void main() {
  testWidgets('learning frames replace playing video and video can resume', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance, fake = QuizPlayer();
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LearningWordContent(const {
              '_id': 'sample',
              'word': 'Chào',
              'videoUrl': 'https://example.com/sample.mp4',
              'imageUrls': [
                'https://example.test/1.jpg',
                'https://example.test/2.jpg',
              ],
            }, showMeaning: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem video ký hiệu'));
    await tester.pumpAndSettle();
    expect(find.byType(SignVideoSurface), findsOneWidget);
    expect(
      tester.getSize(find.byType(SignVideoSurface)).height,
      lessThanOrEqualTo(230),
    );
    final pauses = fake.pauses;
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Xem ảnh 2',
      ),
    );
    await tester.pumpAndSettle();
    expect(fake.pauses, greaterThan(pauses));
    expect(find.byType(SignVideoSurface), findsNothing);
    expect(
      tester.widget<SignPhoto>(find.byType(SignPhoto).first).source,
      'https://example.test/2.jpg',
    );
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Xem ảnh 1',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SignPhoto>(find.byType(SignPhoto).first).source,
      'https://example.test/1.jpg',
    );
    await tester.tap(find.text('Xem video ký hiệu'));
    await tester.pumpAndSettle();
    expect(find.byType(SignVideoSurface), findsOneWidget);
    expect(fake.openedUrls, hasLength(1));
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Xem ảnh 1',
      ),
    );
    await tester.pumpAndSettle();
    fake.playGate = Completer<void>();
    await tester.tap(find.text('Xem video ký hiệu'));
    await tester.pump();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Xem ảnh 2',
      ),
    );
    fake.playGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SignVideoSurface), findsNothing);
    expect(
      tester.widget<SignPhoto>(find.byType(SignPhoto).first).source,
      'https://example.test/2.jpg',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'recall video applies slow playback, replay and pauses for text entry',
    (tester) async {
      final previous = VideoPlayerPlatform.instance, fake = QuizPlayer();
      VideoPlayerPlatform.instance = fake;
      addTearDown(() => VideoPlayerPlatform.instance = previous);
      var pause = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return LearningWordContent(
                    const {
                      'entryId': 'sample',
                      'word': 'Ký hiệu',
                      'videoUrl': 'https://example.com/sample.mp4',
                      'imageUrls': [
                        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7X8AAAAASUVORK5CYII=',
                        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7X8AAAAASUVORK5CYII=',
                      ],
                    },
                    showMeaning: false,
                    quizControls: true,
                    hideQuizLabels: true,
                    pauseVideo: pause,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('0,5×'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem video ký hiệu'));
      await tester.pumpAndSettle();
      expect(fake.speeds, contains(.5));
      expect(fake.playing, isNotEmpty);
      await tester.tap(find.text('Xem lại'));
      await tester.pumpAndSettle();
      expect(fake.positions.last, Duration.zero);
      final beforeFrame = fake.pauses;
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Xem ảnh 2',
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.pauses, greaterThan(beforeFrame));
      expect(find.byType(SignVideoSurface), findsNothing);
      expect(find.text('Thứ tự động tác · Ảnh 2/2'), findsOneWidget);
      await tester.tap(find.text('Xem video ký hiệu'));
      await tester.pumpAndSettle();
      expect(find.byType(SignVideoSurface), findsOneWidget);
      final before = fake.pauses;
      update(() => pause = true);
      await tester.pumpAndSettle();
      expect(fake.pauses, greaterThan(before));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(fake.disposed, isNotEmpty);
    },
  );
}
