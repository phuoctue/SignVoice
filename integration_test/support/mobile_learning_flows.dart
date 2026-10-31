import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/home/home_screen.dart';
import 'package:sign_voice/features/learning/learning_hub.dart';
import 'package:sign_voice/features/learning/learning_widgets.dart';
import 'package:sign_voice/features/learning/topic_learning_screen.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import '../../test/auth_fixtures.dart';

class MobileAuthService extends FakeAuthService {
  @override
  Future<Map<String, bool>> oauthProviders() async => {
    'google': false,
    'facebook': false,
  };
}

class OfflineLearningService extends DemoLearningService {
  bool offline = true;
  @override
  Future<LearningPage> topics({int page = 1, String search = ''}) async {
    if (offline) throw ApiException(message: 'Kết nối bị gián đoạn');
    return super.topics(page: page, search: search);
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void runMobileLearningFlows() {
  testWidgets(
    'login, open lesson, practise with reference, rate and see progress',
    (tester) async {
      final auth = AuthProvider(authService: MobileAuthService());
      await auth.initialize();
      final state = AppState();
      final learning = DemoLearningService();
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          state: state,
          learningService: learning,
          initialScreen: 'S05',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'user@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Test1234');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const ValueKey('auth-submit')));
      expect(find.byType(HomeScreen), findsOneWidget);
      await tapVisible(tester, find.text('Từ điển'));
      expect(find.byType(LearningHub), findsOneWidget);
      await tapVisible(tester, find.text('Chào hỏi'));
      await tapVisible(tester, find.byKey(const ValueKey('learn-start')));
      expect(
        tester
            .widget<TopicLearningScreen>(find.byType(TopicLearningScreen))
            .study,
        isTrue,
      );
      // Reference practice uses the existing self-assessment flow; no camera or API is contacted.
      const wordId = '000000000000000000000010';
      await tapVisible(
        tester,
        find.byKey(const ValueKey('learn-preview-$wordId')),
      );
      expect(find.text('Ý nghĩa'), findsOneWidget);
      expect(find.text('Ví dụ sử dụng'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Đóng'));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('learn-rate-$wordId-REMEMBERED')),
      );
      expect(
        find.byKey(const ValueKey('learn-rate-$wordId-REMEMBERED')),
        findsNothing,
      );
      await tapVisible(tester, find.byTooltip('Quay lại'));
      await tapVisible(tester, find.byTooltip('Quay lại'));
      await tapVisible(tester, find.text('Đang học'));
      expect(find.text('Đã nhớ 1 / 10 từ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );

  testWidgets(
    'recover from offline topics and create, reopen and read a personal word',
    (tester) async {
      final auth = await authenticatedProvider();
      final state = AppState();
      final learning = OfflineLearningService();
      await tester.pumpWidget(
        SignVoiceApp(
          key: UniqueKey(),
          auth: auth,
          state: state,
          learningService: learning,
          initialScreen: 'S22',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kết nối bị gián đoạn'), findsOneWidget);
      learning.offline = false;
      await tapVisible(tester, find.text('Thử lại'));
      expect(find.text('Chào hỏi'), findsOneWidget);
      await tapVisible(tester, find.text('Từ của tôi'));
      await tapVisible(tester, find.text('Tạo từ mới'));
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Chúc ngủ ngon');
      await tester.enterText(fields.at(1), 'Lời chúc trước khi đi ngủ.');
      await tester.ensureVisible(fields.at(2));
      await tester.enterText(fields.at(2), 'Chúc bạn ngủ ngon.');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.byKey(const ValueKey('personal-word-save')),
      );
      expect(find.text('Chúc ngủ ngon'), findsOneWidget);
      await tapVisible(tester, find.text('Khám phá'));
      await tapVisible(tester, find.text('Từ của tôi'));
      await tapVisible(tester, find.text('Chúc ngủ ngon'));
      expect(
        find.descendant(
          of: find.byType(LearningWordContent),
          matching: find.text('Lời chúc trước khi đi ngủ.'),
        ),
        findsOneWidget,
      );
      expect(find.text('“Chúc bạn ngủ ngon.”'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Đóng'));
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );
}
