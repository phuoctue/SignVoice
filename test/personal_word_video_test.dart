import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sign_voice/features/learning/personal_word_form.dart';
import 'package:sign_voice/features/learning/record_video_dialog.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/widgets/ui.dart';

class PersonalVideoService extends LearningService {
  List<int>? uploaded;
  LearningRecord? saved;
  @override
  Future<String> uploadVideo(
    Stream<List<int>> Function() openStream,
    int length,
  ) async {
    uploaded = await openStream().expand((chunk) => chunk).toList();
    return '/personal-videos/${'a' * 24}/${'b' * 64}.mp4?expires=123&signature=test';
  }

  @override
  Future<void> saveWord(LearningRecord word, {String? id}) async {
    saved = word;
  }
}

void main() {
  late Directory folder;
  late File video;
  const picker = MethodChannel('plugins.flutter.io/image_picker');
  setUp(() {
    folder = Directory.systemTemp.createTempSync('signvoice-personal-video-');
    video = File('${folder.path}/my-sign.mov')
      ..writeAsBytesSync([1, 2, 3, 255]);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null);
    folder.deleteSync(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester,
    PersonalVideoService service, {
    Future<XFile?> Function(BuildContext)? recorder,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalWordForm(
          service: service,
          videoRecorder: recorder,
          word: {
            '_id': 'word',
            'word': 'Xin chào',
            'definition': 'Lời chào hỏi',
            'notes': 'Ghi chú cũ',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(
    WidgetTester tester,
    PersonalVideoService service,
    String label,
  ) async {
    await tester.ensureVisible(find.text(label));
    await tester.runAsync(() async {
      await tester.tap(find.text(label));
      for (var i = 0; i < 100 && service.uploaded == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'personal form picks a local video, removes URL and note inputs, and saves private media',
    (tester) async {
      final service = PersonalVideoService();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(picker, (
        call,
      ) async {
        expect(call.method, 'pickVideo');
        return video.path;
      });
      await mount(tester, service);
      expect(find.text('Link video HTTPS (không bắt buộc)'), findsNothing);
      expect(find.text('Mẹo ghi nhớ / nguồn tham khảo'), findsNothing);
      expect(find.text('Quay video mới'), findsOneWidget);
      await choose(tester, service, 'Chọn video từ máy');
      expect(service.uploaded, [1, 2, 3, 255]);
      expect(find.text('my-sign.mov'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(AppButton, 'Lưu từ'));
      await tester.tap(find.widgetWithText(AppButton, 'Lưu từ'));
      await tester.pumpAndSettle();
      expect(service.saved!['videoUrl'], startsWith('/personal-videos/'));
      expect(service.saved!.containsKey('notes'), isFalse);
    },
  );

  testWidgets('a recorded video uses the same private upload flow', (
    tester,
  ) async {
    final service = PersonalVideoService();
    var recorded = false;
    await mount(
      tester,
      service,
      recorder: (_) async {
        recorded = true;
        return XFile(video.path);
      },
    );
    await choose(tester, service, 'Quay video mới');
    expect(recorded, isTrue);
    expect(service.uploaded, [1, 2, 3, 255]);
    expect(find.text('Video vừa quay'), findsOneWidget);
    await tester.ensureVisible(find.text('Bỏ video'));
    await tester.tap(find.text('Bỏ video'));
    await tester.pumpAndSettle();
    expect(find.text('Video vừa quay'), findsNothing);
    expect(find.text('Chọn video từ máy'), findsOneWidget);
  });

  testWidgets('camera failure offers choosing an existing video', (
    tester,
  ) async {
    const camera = MethodChannel('plugins.flutter.io/camera');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      camera,
      (_) async => [],
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        camera,
        null,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: RecordVideoDialog()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không mở được camera'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Bắt đầu quay'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
