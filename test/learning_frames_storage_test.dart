import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/features/learning/learning_widgets.dart';

void main() {
  testWidgets('expansion state cannot be restored as a frame scroll offset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ExpansionTile(
              title: const Text('Xem mẫu'),
              children: [
                LearningWordContent(const {
                  '_id': 'fixture',
                  'word': 'fixture',
                  'imageUrls': [
                    'https://example.test/1.jpg',
                    'https://example.test/2.jpg',
                  ],
                }, showMeaning: false),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Xem mẫu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Thứ tự động tác · Ảnh 1/2'), findsOneWidget);
  });
}
