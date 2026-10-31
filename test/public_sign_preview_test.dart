import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:sign_voice/widgets/public_sign_preview.dart';

import 'sign_video_dialog_test.dart' show FakeSignPlayer;

void main() {
  testWidgets(
    'only the current public preview plays and all players are released',
    (tester) async {
      final original = VideoPlayerPlatform.instance, player = FakeSignPlayer();
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final name in ['một', 'hai'])
                  PublicSignPreview(
                    word: {
                      'word': name,
                      'videoUrl': 'https://example.org/$name.mp4',
                    },
                    height: 180,
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Xem trước video một'));
      await tester.pumpAndSettle();
      expect(player.playing, [1]);
      await tester.tap(find.byTooltip('Xem trước video hai'));
      await tester.pumpAndSettle();
      expect(player.playing, [1, 2]);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      expect(player.disposed, contains(1));
      expect(find.byTooltip('Xem trước video một'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      expect(player.disposed, containsAll([1, 2]));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'autoplay honors reduced motion while explicit playback remains available',
    (tester) async {
      final original = VideoPlayerPlatform.instance, player = FakeSignPlayer();
      VideoPlayerPlatform.instance = player;
      addTearDown(() => VideoPlayerPlatform.instance = original);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Scaffold(
                body: PublicSignPreview(
                  autoplay: true,
                  height: 220,
                  word: {
                    'word': 'mẫu',
                    'videoUrl': 'https://example.org/sample.mp4',
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(player.openedUrls, isEmpty);
      await tester.tap(find.byTooltip('Xem trước video mẫu'));
      await tester.pumpAndSettle();
      expect(player.playing, [1]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
      expect(player.disposed, [1]);
      expect(tester.takeException(), isNull);
    },
  );
}
