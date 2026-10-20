import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/features/speech/sign_sequence_panel.dart';

Widget harness(String text, SequenceLoader loader) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: SignSequencePanel(text: text, loader: loader),
    ),
  ),
);

void main() {
  testWidgets(
    'opens the selected keyframe while retaining chronological images',
    (tester) async {
      await tester.pumpWidget(
        harness(
          'chào',
          (_) async => {
            'segments': [
              {
                'type': 'sign',
                'text': 'chào',
                'word': 'chào',
                'thumbnailUrl': 'https://example.org/2.jpg',
                'imageUrls': [
                  'https://example.org/1.jpg',
                  'https://example.org/2.jpg',
                  'https://example.org/3.jpg',
                ],
              },
            ],
          },
        ),
      );
      await tester.tap(find.text('Xem ký hiệu'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ảnh 2/3 · Vuốt để xem thứ tự động tác'),
        findsOneWidget,
      );
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.initialPage,
        1,
      );
    },
  );
  testWidgets('loads on explicit request and shows missing words in order', (
    tester,
  ) async {
    var calls = 0;
    Future<Map<String, dynamic>> load(String text) async {
      calls++;
      expect(text, 'Xin chào, tôi là An');
      return {
        'segments': [
          {
            'type': 'sign',
            'text': 'Xin chào',
            'word': 'xin chào',
            'imageUrls': [],
            'videoUrl': 'https://example.org/a.mp4',
          },
          {'type': 'punctuation', 'text': ','},
          {'type': 'missing', 'text': 'tôi'},
          {'type': 'missing', 'text': 'là'},
          {'type': 'missing', 'text': 'An'},
        ],
      };
    }

    await tester.pumpWidget(harness('Xin chào, tôi là An', load));
    expect(calls, 0);
    await tester.tap(find.text('Xem ký hiệu'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('1. Xin chào'), findsOneWidget);
    expect(find.text('2. tôi'), findsOneWidget);
    expect(find.text('3. là'), findsOneWidget);
    expect(find.text('4. An'), findsOneWidget);
    expect(find.text('Xem động tác'), findsOneWidget);
    expect(
      find.text('Chưa có ký hiệu đã xuất bản cho đoạn này.'),
      findsNWidgets(3),
    );
  });
  testWidgets(
    'editing invalidates an in-flight result without discarding new text',
    (tester) async {
      final old = Completer<Map<String, dynamic>>();
      Future<Map<String, dynamic>> load(String text) => old.future;
      await tester.pumpWidget(harness('chào', load));
      await tester.tap(find.text('Xem ký hiệu'));
      await tester.pump();
      await tester.pumpWidget(harness('rau', load));
      old.complete({
        'segments': [
          {'type': 'missing', 'text': 'chào'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('1. chào'), findsNothing);
      expect(
        tester.widget<SignSequencePanel>(find.byType(SignSequencePanel)).text,
        'rau',
      );
    },
  );
  testWidgets('network errors allow retry and keep the transcript', (
    tester,
  ) async {
    var attempts = 0;
    Future<Map<String, dynamic>> load(String text) async {
      if (++attempts == 1) throw StateError('offline');
      return {
        'segments': [
          {'type': 'missing', 'text': text},
        ],
      };
    }

    await tester.pumpWidget(harness('cảm ơn', load));
    await tester.tap(find.text('Xem ký hiệu'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Văn bản của bạn vẫn được giữ nguyên'),
      findsOneWidget,
    );
    await tester.tap(find.text('Xem ký hiệu'));
    await tester.pumpAndSettle();
    expect(find.text('1. cảm ơn'), findsOneWidget);
  });
}
