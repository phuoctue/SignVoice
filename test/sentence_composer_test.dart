import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/recognition/live_camera_screen.dart';
import 'package:sign_voice/features/recognition/recognition_screens.dart';

Future<void> showComposer(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    AppScope(
      state: state,
      child: MaterialApp(
        home: const SentenceScreen(),
        routes: {'S10': (_) => const LiveCameraScreen()},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> addText(WidgetTester tester, String text) async {
  final add = find.widgetWithText(FilledButton, 'Thêm từ');
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
  expect(find.text('Thêm từ vào câu'), findsOneWidget);
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'sentence joins fragments naturally and preserves terminal punctuation',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      state.addWord('  Xin chào  ');
      state.addWord('bạn');
      expect(state.sentence, ['Xin chào', 'bạn']);
      expect(state.sentenceText, 'Xin chào bạn.');
      state.sentence.clear();
      state.addWord('Bạn khỏe không?');
      expect(state.sentenceText, 'Bạn khỏe không?');
    },
  );

  test('empty input does not add a chip or alter the recognized fragment', () {
    final state = AppState();
    addTearDown(state.dispose);
    state.addWord('a');
    var changes = 0;
    state.addListener(() => changes++);
    state.addWord('   \n ');
    expect(state.sentence, ['a']);
    expect(changes, 0);
  });

  testWidgets('manual add keeps recognized content and stays out of camera', (
    tester,
  ) async {
    final state = AppState()..addWord('a');
    addTearDown(state.dispose);
    await showComposer(tester, state);
    await addText(tester, '  bàn tay  ');
    expect(state.sentence, ['a', 'bàn tay']);
    expect(find.text('a bàn tay.'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(2));
    expect(find.byType(LiveCameraScreen), findsNothing);
    await addText(tester, 'rau');
    expect(state.sentence, ['a', 'bàn tay', 'rau']);
    expect(find.byType(LiveCameraScreen), findsNothing);
  });

  testWidgets('cancel and blank additions preserve the current sentence', (
    tester,
  ) async {
    final state = AppState()..addWord('chào');
    addTearDown(state.dispose);
    await showComposer(tester, state);
    await addText(tester, '   ');
    expect(state.sentence, ['chào']);
    await tester.tap(find.widgetWithText(FilledButton, 'Thêm từ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'không thêm');
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(state.sentence, ['chào']);
    expect(find.byType(LiveCameraScreen), findsNothing);
  });

  testWidgets(
    'only explicit recognition opens camera consent and retains words',
    (tester) async {
      final state = AppState()..addWord('nghe');
      addTearDown(state.dispose);
      await showComposer(tester, state);
      final camera = find.widgetWithText(TextButton, 'Nhận diện tiếp');
      await tester.ensureVisible(camera);
      await tester.tap(camera);
      await tester.pumpAndSettle();
      expect(find.byType(LiveCameraScreen), findsOneWidget);
      expect(find.text('Cho phép camera'), findsOneWidget);
      expect(state.sentence, ['nghe']);
      await tester.tap(find.text('Để sau'));
      await tester.pumpAndSettle();
      expect(find.byType(SentenceScreen), findsOneWidget);
      expect(state.sentence, ['nghe']);
    },
  );

  testWidgets('editing uses readable sentence text without inserted commas', (
    tester,
  ) async {
    final state = AppState()
      ..addWord('Xin chào')
      ..addWord('bạn');
    addTearDown(state.dispose);
    await showComposer(tester, state);
    final edit = find.widgetWithText(FilledButton, 'Chỉnh sửa câu');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, 'Xin chào bạn');
    await tester.enterText(find.byType(TextField), 'Bạn khỏe không?');
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    expect(state.sentenceText, 'Bạn khỏe không?');
  });
}
