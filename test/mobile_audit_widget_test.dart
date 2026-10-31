import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/learning/learning_widgets.dart';
import 'package:sign_voice/features/learning/personal_word_form.dart';
import 'package:sign_voice/features/learning/review_quiz_screen.dart';
import 'package:sign_voice/features/learning/topic_learning_screen.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import 'auth_fixtures.dart';

class PendingLoginService extends FakeAuthService {
  final response = Completer<UserModel>();
  @override
  Future<UserModel> login({required String email, required String password}) =>
      response.future;
}

class RetryQuizService extends DemoLearningService {
  final first = Completer<LearningRecord>();
  int requests = 0;
  @override
  Future<LearningRecord> quiz(String id) async {
    if (requests++ == 0) return first.future;
    return {
      '_id': id,
      'topicId': DemoLearningService.topicId,
      'questions': [
        {
          'entryId': 'word',
          'word': 'xin chào',
          'prompt': 'Làm ký hiệu xin chào',
        },
      ],
    };
  }
}

void main() {
  testWidgets('mobile pages and thumbnails support large text and landscape', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    for (final size in [
      const Size(320, 640),
      const Size(375, 667),
      const Size(844, 390),
    ]) {
      tester.view.physicalSize = size;
      for (final screen in ['S01', 'S03', 'S05', 'S08', 'S22', 'S25']) {
        final state = AppState()
          ..fontScale = 2
          ..themeMode = size.width == 375 ? ThemeMode.dark : ThemeMode.light;
        await tester.pumpWidget(
          SignVoiceApp(
            key: UniqueKey(),
            auth: auth,
            state: state,
            initialScreen: screen,
            learningService: DemoLearningService(),
          ),
        );
        // Do not fire the splash's navigation timer or settle its spinner.
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: '$screen at $size');
        if (screen == 'S05') {
          expect(tester.getSize(find.byType(Scaffold).first).width, size.width);
        }
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      }
    }
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const Scaffold(
            body: Center(child: SignPhoto(null, width: 66, height: 68)),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull, reason: 'thumbnail fallback');
  });

  testWidgets('personal word form keeps the focused field above the keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editPersonalWord(context, DemoLearningService()),
              child: const Text('Mở form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở form'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final notes = find.byType(TextFormField).last;
    await tester.ensureVisible(notes);
    await tester.showKeyboard(notes);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(notes).dy, lessThanOrEqualTo(340));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed quiz load can be retried from the same screen', (
    tester,
  ) async {
    final service = RetryQuizService();
    await tester.pumpWidget(
      Provider<LearningService>.value(
        value: service,
        child: const MaterialApp(home: ReviewQuizScreen(quizId: 'quiz')),
      ),
    );
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    service.first.completeError(ApiException(message: 'Kết nối bị gián đoạn'));
    await tester.pumpAndSettle();
    expect(find.text('Kết nối bị gián đoạn'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Làm ký hiệu xin chào'), findsOneWidget);
    expect(find.text('Kết nối bị gián đoạn'), findsNothing);
  });

  testWidgets(
    'pending login disables resubmission and retains credentials on error',
    (tester) async {
      final service = PendingLoginService();
      final auth = AuthProvider(authService: service);
      await auth.initialize();
      final state = AppState();
      addTearDown(auth.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SignVoiceApp(initialScreen: 'S05', auth: auth, state: state),
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'user@example.com');
      await tester.enterText(fields.at(1), 'Test1234');
      final login = find.widgetWithText(FilledButton, 'Đăng nhập');
      await tester.ensureVisible(login);
      await tester.tap(login);
      await tester.pump();
      expect(tester.widget<FilledButton>(login).onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      service.response.completeError(ApiException(message: 'Sai mật khẩu'));
      await tester.pumpAndSettle();
      expect(find.text('Sai mật khẩu'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'user@example.com',
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'Test1234',
      );
      expect(tester.widget<FilledButton>(login).onPressed, isNotNull);
    },
  );

  testWidgets(
    'cold and warm learning routes match and malformed links show recovery',
    (tester) async {
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      final state = AppState();
      addTearDown(state.dispose);
      final route = '/learn/topic/${DemoLearningService.topicId}?study=1';
      tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final service = DemoLearningService()..enrolled = true;
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          state: state,
          initialScreen: 'S08',
          learningService: service,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TopicLearningScreen>(find.byType(TopicLearningScreen))
            .study,
        isTrue,
      );
      final context = tester.element(find.byType(TopicLearningScreen));
      Navigator.of(context).pushNamed('/learn/topic');
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy trang'), findsOneWidget);
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(find.byType(TopicLearningScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(TopicLearningScreen)))
          .pushNamed(route);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TopicLearningScreen>(find.byType(TopicLearningScreen))
            .study,
        isTrue,
      );
    },
  );
}
