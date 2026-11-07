import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/features/learning/learning_widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'sign_video_dialog_test.dart' show FakeSignPlayer;

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <MethodCall>[];
  var launchResult = true;

  setUp(() {
    launches.clear();
    launchResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          launches.add(call);
          return launchResult;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester, String url) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LearningWordContent({
            '_id': 'word',
            'word': 'chào',
            'videoUrl': url,
          }),
        ),
      ),
    ),
  );

  testWidgets('Vimeo page opens externally without creating a video player', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    final player = FakeSignPlayer();
    VideoPlayerPlatform.instance = player;
    addTearDown(() => VideoPlayerPlatform.instance = previous);

    await mount(tester, 'https://vimeo.com/666328674');
    await tester.tap(find.text('Xem trên Vimeo'));
    await tester.pumpAndSettle();

    expect(launches.single.method, 'launch');
    expect(launches.single.arguments['url'], 'https://vimeo.com/666328674');
    expect(player.nextId, 0);
    expect(find.textContaining('Chưa tải được video'), findsNothing);
  });

  testWidgets('failed external launch shows a retryable error', (tester) async {
    launchResult = false;
    await mount(tester, 'https://vimeo.com/666328674');
    await tester.tap(find.text('Xem trên Vimeo'));
    await tester.pumpAndSettle();
    expect(
      find.text('Không mở được link video. Vui lòng thử lại.'),
      findsOneWidget,
    );
    launchResult = true;
    await tester.tap(find.text('Xem trên Vimeo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không mở được link'), findsNothing);
  });

  testWidgets('direct MP4 still initializes and plays inside the app', (
    tester,
  ) async {
    final previous = VideoPlayerPlatform.instance;
    final player = FakeSignPlayer();
    VideoPlayerPlatform.instance = player;
    addTearDown(() => VideoPlayerPlatform.instance = previous);

    await mount(tester, 'https://cdn.example.org/chao.mp4');
    await tester.tap(find.text('Xem video ký hiệu'));
    await tester.pump();
    await tester.pump();

    expect(player.playing, contains(1));
    expect(launches, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
