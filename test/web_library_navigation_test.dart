import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/features/learning/collection_widgets.dart';

import 'auth_fixtures.dart';

class LibraryService extends DemoLearningService {
  int topicsReads = 0, progressReads = 0;
  @override
  Future<LearningPage> topics({int page = 1, String search = ''}) {
    topicsReads++;
    return super.topics(page: page, search: search);
  }

  @override
  Future<LearningPage> progress({int page = 1, String stage = 'ALL'}) {
    progressReads++;
    return super.progress(page: page, stage: stage);
  }

  @override
  Future<LearningRecord> collectionRead(
    String path, {
    int page = 1,
    String search = '',
  }) async => {
    'items': [],
    'pagination': {'page': 1, 'pages': 1, 'total': 0},
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'library changes query tabs and retains native browser route history',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      final service = LibraryService()..enrolled = true;
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: 'S22',
          state: AppState(),
          auth: auth,
          learningService: service,
          adminService: DemoDictionaryService(),
        ),
      );
      await tester.pumpAndSettle();
      final tabs = find.byType(LearningTabs);
      Future<void> select(String name) async {
        await tester.tap(find.descendant(of: tabs, matching: find.text(name)));
        await tester.pumpAndSettle();
      }

      final router = GoRouter.of(tester.element(tabs));
      await select('Đang học');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['tab'],
        '1',
      );
      expect(find.text('Phân tích tiến độ cá nhân'), findsOneWidget);
      await select('Khám phá');
      expect(find.text('Học ký hiệu theo chủ đề'), findsOneWidget);
      await select('Bộ sưu tập');
      expect(find.text('Tạo bộ sưu tập'), findsOneWidget);
      await select('Đang học');
      await select('Khám phá');
      expect(find.text('Học ký hiệu theo chủ đề'), findsOneWidget);
      router.go('/learn?tab=1');
      await tester.pumpAndSettle();
      router.go('/learn?tab=0');
      await tester.pumpAndSettle();
      expect(tester.widget<LearningTabs>(tabs).selected, 0);
      expect(find.text('Học ký hiệu theo chủ đề'), findsOneWidget);
      await router.routeInformationProvider.didPushRouteInformation(
        RouteInformation(uri: Uri.parse('/learn?tab=1')),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<LearningTabs>(tabs).selected, 1);
      await tester.tap(find.byTooltip('Thư viện ký hiệu'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/dictionary');
      expect(find.text('Học ký hiệu theo chủ đề'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
