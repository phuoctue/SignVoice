import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/recognition/recognition_screens.dart';
import 'package:sign_voice/features/speech/speech_screens.dart';
import 'package:sign_voice/services/sign_ai/speech_output.dart';
import 'package:sign_voice/widgets/device_permission_page.dart';
import 'package:sign_voice/widgets/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const tts = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(tts, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('signvoice/speech'),
      null,
    );
  });

  testWidgets(
    'microphone instructions fit above fixed actions on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DevicePermissionPage(
            camera: false,
            onAllow: () {},
            alternativeAction: TextButton(
              onPressed: () {},
              child: const Text('Nhập văn bản để xem ký hiệu'),
            ),
          ),
        ),
      );
      final noticeBottom = tester.getBottomLeft(find.byType(Notice)).dy;
      final viewportBottom = tester
          .getBottomLeft(find.byType(SingleChildScrollView))
          .dy;
      expect(noticeBottom, lessThanOrEqualTo(viewportBottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transcript edits in the existing card, cancels, validates and commits',
    (tester) async {
      final state = AppState()..transcript = 'xin chào';
      addTearDown(state.dispose);
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: const MaterialApp(home: TranscriptScreen()),
        ),
      );
      final edit = find.text('Chỉnh sửa văn bản');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final field = find.byKey(const ValueKey('transcript-editor'));
      expect(field, findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.enterText(field, 'bản nháp');
      await tester.ensureVisible(find.text('Hủy'));
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(state.transcript, 'xin chào');
      tester.view.resetViewInsets();
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(field, '  ');
      await tester.ensureVisible(find.text('Lưu văn bản'));
      await tester.tap(find.text('Lưu văn bản'));
      await tester.pumpAndSettle();
      expect(state.transcript, 'xin chào');
      expect(find.text('Vui lòng nhập văn bản.'), findsOneWidget);
      await tester.enterText(field, '  chúc bạn một ngày tốt lành  ');
      await tester.ensureVisible(find.text('Lưu văn bản'));
      await tester.tap(find.text('Lưu văn bản'));
      await tester.pumpAndSettle();
      expect(state.transcript, 'chúc bạn một ngày tốt lành');
      expect(find.byKey(const ValueKey('transcript-editor')), findsNothing);
      expect(find.text('chúc bạn một ngày tốt lành'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('speech falls back to a Vietnamese language alias', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(tts, (call) async {
      calls.add(call);
      if (call.method == 'isLanguageAvailable') return call.arguments == 'vi';
      return 1;
    });
    await SpeechOutput().speak('xin chào', speed: 1.5, pitch: 1.2);
    expect(calls.firstWhere((c) => c.method == 'setLanguage').arguments, 'vi');
    expect(calls.singleWhere((c) => c.method == 'speak').arguments, 'xin chào');
    expect(calls.firstWhere((c) => c.method == 'setSpeechRate').arguments, .75);
  });

  test(
    'speech selects a listed Vietnamese voice when locale probing fails',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(tts, (call) async {
        calls.add(call);
        if (call.method == 'isLanguageAvailable') return false;
        if (call.method == 'getVoices') {
          return [
            {'name': 'English', 'locale': 'en-US'},
            {'name': 'Vietnamese', 'locale': 'vi-VN'},
          ];
        }
        return 1;
      });
      await SpeechOutput().speak('xin chào');
      expect(calls.singleWhere((c) => c.method == 'setVoice').arguments, {
        'name': 'Vietnamese',
        'locale': 'vi-VN',
      });
      expect(calls.where((c) => c.method == 'speak'), hasLength(1));
    },
  );

  test(
    'reconnects the default engine to see Vietnamese data just installed',
    () async {
      var refreshed = false;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(tts, (call) async {
        calls.add(call);
        if (call.method == 'isLanguageAvailable') return refreshed;
        if (call.method == 'getVoices') return [];
        if (call.method == 'getDefaultEngine') return 'installed.engine';
        if (call.method == 'setEngine') {
          refreshed = true;
          return 1;
        }
        return 1;
      });
      await SpeechOutput().speak('xin chào');
      expect(
        calls
            .where((call) => call.method == 'setEngine')
            .map((call) => call.arguments),
        ['installed.engine'],
      );
      expect(calls.where((call) => call.method == 'speak'), hasLength(1));
    },
  );

  test('uses an installed Vietnamese engine if the current engine only supports another language', () async {
    var engine = 'chinese.engine';
    messenger.setMockMethodCallHandler(tts, (call) async {
      if (call.method == 'isLanguageAvailable') {
        return engine == 'vietnamese.engine';
      }
      if (call.method == 'getVoices') return [];
      if (call.method == 'getDefaultEngine') return 'chinese.engine';
      if (call.method == 'getEngines') {
        return ['chinese.engine', 'vietnamese.engine'];
      }
      if (call.method == 'setEngine') {
        engine = call.arguments as String;
        return 1;
      }
      return 1;
    });
    expect(await SpeechOutput().refreshVietnameseVoice(), isTrue);
    expect(engine, 'vietnamese.engine');
  });

  testWidgets(
    'returning from voice settings rechecks without speaking automatically',
    (tester) async {
      var installed = false, spoken = 0;
      messenger.setMockMethodCallHandler(tts, (call) async {
        if (call.method == 'isLanguageAvailable') return installed;
        if (call.method == 'getVoices') return [];
        if (call.method == 'getDefaultEngine') return 'engine';
        if (call.method == 'getEngines') return ['engine'];
        if (call.method == 'speak') spoken++;
        return 1;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel('signvoice/speech'),
        (_) async => true,
      );
      final state = AppState()..addWord('xin chào');
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: const MaterialApp(home: VoicePlaybackScreen()),
        ),
      );
      await tester.tap(find.byTooltip('Phát'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cài giọng tiếng Việt'));
      await tester.tap(find.text('Cài giọng tiếng Việt'));
      await tester.pumpAndSettle();
      installed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Đã nhận giọng tiếng Việt. Bấm Phát để nghe.'),
        findsOneWidget,
      );
      expect(spoken, 0);
      expect(find.text('Cài giọng tiếng Việt'), findsNothing);
    },
  );

  testWidgets(
    'missing Vietnamese voice provides installation instead of a raw exception',
    (tester) async {
      messenger.setMockMethodCallHandler(tts, (call) async {
        if (call.method == 'isLanguageAvailable') return false;
        if (call.method == 'getVoices') return [];
        return 1;
      });
      var opened = false;
      messenger.setMockMethodCallHandler(
        const MethodChannel('signvoice/speech'),
        (call) async {
          expect(call.method, 'openVoiceSettings');
          opened = true;
          return true;
        },
      );
      final state = AppState()..addWord('xin chào');
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: const MaterialApp(home: VoicePlaybackScreen()),
        ),
      );
      await tester.tap(find.byTooltip('Phát'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bad state:'), findsNothing);
      await tester.ensureVisible(find.text('Cài giọng tiếng Việt'));
      await tester.tap(find.text('Cài giọng tiếng Việt'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      expect(state.sentenceText, 'xin chào.');
    },
  );

  test(
    'a missing Vietnamese voice never silently reads using an English voice',
    () async {
      var spoken = false;
      messenger.setMockMethodCallHandler(tts, (call) async {
        if (call.method == 'isLanguageAvailable') return false;
        if (call.method == 'getVoices') {
          return [
            {'name': 'English', 'locale': 'en-US'},
          ];
        }
        if (call.method == 'speak') spoken = true;
        return 1;
      });
      await expectLater(
        SpeechOutput().speak('xin chào'),
        throwsA(isA<MissingVietnameseVoiceException>()),
      );
      expect(spoken, isFalse);
    },
  );

  test(
    'stopping during voice initialization prevents a late utterance',
    () async {
      final checking = Completer<void>();
      final available = Completer<bool>();
      var spoken = false;
      messenger.setMockMethodCallHandler(tts, (call) async {
        if (call.method == 'isLanguageAvailable') {
          checking.complete();
          return available.future;
        }
        if (call.method == 'speak') spoken = true;
        return 1;
      });
      final output = SpeechOutput();
      final pending = output.speak('xin chào');
      await checking.future;
      await output.stop();
      available.complete(true);
      await pending;
      expect(spoken, isFalse);
    },
  );

  test(
    'a device synthesis failure is reported instead of a false success',
    () async {
      messenger.setMockMethodCallHandler(tts, (call) async {
        if (call.method == 'isLanguageAvailable') return true;
        if (call.method == 'speak') return 0;
        return 1;
      });
      await expectLater(
        SpeechOutput().speak('xin chào'),
        throwsA(isA<SpeechOutputException>()),
      );
    },
  );
}
