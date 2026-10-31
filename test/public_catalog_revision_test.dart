import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/widgets/public_catalog_page.dart';

import 'auth_fixtures.dart';

class PublicDictionaryFixture extends DemoDictionaryService {
  final calls = <({int page, String search, String sort, String? category})>[];
  int categoryReads = 0;
  @override
  Future<List<AdminRecord>> activeCategories() async {
    categoryReads++;
    return [
      {'_id': 'greeting', 'name': 'Giao tiếp', 'wordCount': 1234},
    ];
  }

  @override
  Future<AdminPageData> published({
    int page = 1,
    String search = '',
    String? categoryId,
    String sort = 'word_asc',
  }) async {
    calls.add((page: page, search: search, sort: sort, category: categoryId));
    return AdminPageData(
      [
        for (var i = 0; i < 4; i++)
          {
            '_id': 'word-$i',
            'word': 'chào $page-$i',
            'categoryId': {'name': 'Giao tiếp'},
          },
      ],
      page,
      62,
      1234,
    );
  }
}

void main() {
  for (final size in [
    const Size(1440, 1000),
    const Size(768, 1024),
    const Size(375, 812),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'public dictionary has clear navigation at $size and text $scale',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final auth = AuthProvider(authService: FakeAuthService()),
              state = AppState(),
              service = PublicDictionaryFixture();
          await tester.pumpWidget(
            SignVoiceApp(
              webRouting: true,
              initialScreen: '/dictionary',
              auth: auth,
              state: state,
              adminService: service,
              learningService: DemoLearningService(),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(PublicCatalogPage), findsOneWidget);
          if (size.width == 1440 && scale == 1) {
            final dictionaryLink = find.widgetWithText(
              TextButton,
              'Từ điển ký hiệu',
            );
            final collectionLink = find.widgetWithText(
              TextButton,
              'Bộ sưu tập công khai',
            );
            expect(
              (tester.getCenter(dictionaryLink).dy -
                      tester.getCenter(collectionLink).dy)
                  .abs(),
              lessThan(1),
            );
          }
          expect(find.byType(NavigationBar), findsNothing);
          expect(find.text('Đăng nhập'), findsOneWidget);
          expect(find.text('Đăng ký'), findsOneWidget);
          expect(find.textContaining('1.234 ký hiệu'), findsOneWidget);
          expect(service.calls.single.sort, '');
          await tester.ensureVisible(find.byTooltip('Yêu thích chào 1-0'));
          await tester.tap(find.byTooltip('Yêu thích chào 1-0'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Đăng nhập để lưu ký hiệu'),
            findsOneWidget,
          );
          expect(auth.isAuthenticated, false);
          await tester.tap(find.text('Để sau'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          auth.dispose();
          state.dispose();
        },
      );
    }
  }
  testWidgets(
    'search debounces, clears, retains category cache and jumps to a requested page',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = AuthProvider(authService: FakeAuthService()),
          state = AppState(),
          service = PublicDictionaryFixture();
      await tester.pumpWidget(
        SignVoiceApp(
          webRouting: true,
          initialScreen: '/dictionary',
          auth: auth,
          state: state,
          adminService: service,
          learningService: DemoLearningService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      final field = find.byKey(const ValueKey('dictionary-search'));
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, true);
      await tester.enterText(field, 'ch');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(field, 'chào');
      await tester.pump(const Duration(milliseconds: 360));
      await tester.pumpAndSettle();
      expect(service.calls.map((call) => call.search), ['', 'chào']);
      expect(service.categoryReads, 1);
      await tester.tap(find.byTooltip('Xóa tìm kiếm'));
      await tester.pumpAndSettle();
      expect(service.calls.last.search, '');
      final page = find.byKey(const ValueKey('dictionary-page'));
      await tester.ensureVisible(page);
      await tester.enterText(page, '42');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();
      expect(service.calls.last.page, 42);
      expect(service.categoryReads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );
}
