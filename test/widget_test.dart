import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/features/library/library_screens.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/core/navigation.dart';
import 'package:sign_voice/features/home/home_screen.dart';
import 'package:sign_voice/features/learning/learning_widgets.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/screens/admin/admin_ui.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';

import 'auth_fixtures.dart';

class ChangingDictionaryCategories extends DemoDictionaryService {
  bool archived = false;
  String? lastCategory;
  String? lastSort;
  int? lastPage;
  String? lastSearch;
  bool multiPage = false;
  int categoryLoads = 0;
  @override
  Future<List<AdminRecord>> activeCategories() async {
    categoryLoads++;
    return [
      ...await super.activeCategories(),
      {'_id': 'empty', 'name': 'Từ vựng khác', 'wordCount': 0},
    ].where((category) => !archived || category['_id'] != 'Ăn uống').toList();
  }

  @override
  Future<AdminPageData> published({
    int page = 1,
    String search = '',
    String? categoryId,
    String sort = 'word_asc',
  }) async {
    lastCategory = categoryId;
    lastSort = sort;
    lastPage = page;
    lastSearch = search;
    final result = await super.published(
      page: page,
      search: search,
      categoryId: categoryId,
      sort: sort,
    );
    return AdminPageData(result.items, page, multiPage ? 3 : 1, result.total);
  }
}

Widget dictionaryHarness(
  AuthProvider auth,
  AppState state,
  AdminWorkspaceService service,
) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: auth),
    Provider<AdminWorkspaceService>.value(value: service),
  ],
  child: AppScope(
    state: state,
    child: const MaterialApp(home: DictionaryScreen()),
  ),
);

Future<void> openDictionaryPicker(WidgetTester tester, String label) async {
  final field = find.byWidgetPredicate(
    (widget) => widget is AdminSelectField && widget.label == label,
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('admin-choice-menu')), findsOneWidget);
}

Finder dictionaryPickerOption(String label) => find.descendant(
  of: find.byKey(const ValueKey('admin-choice-menu')),
  matching: find.text(label),
);

void main() {
  testWidgets(
    'dictionary sort resets page and persists through category and search filters',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      final state = AppState(),
          service = ChangingDictionaryCategories()..multiPage = true;
      await tester.pumpWidget(dictionaryHarness(auth, state, service));
      await tester.pumpAndSettle();
      expect(service.lastSort, '');
      expect(find.text('Mới xuất bản'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Trang sau'));
      await tester.tap(find.byTooltip('Trang sau'));
      await tester.pumpAndSettle();
      expect(service.lastPage, 2);
      await openDictionaryPicker(tester, 'Sắp xếp');
      await tester.tap(dictionaryPickerOption('Tên: Z–A'));
      await tester.pumpAndSettle();
      expect(service.lastPage, 1);
      expect(service.lastSort, 'word_desc');
      await openDictionaryPicker(tester, 'Chủ đề');
      expect(dictionaryPickerOption('Từ vựng khác'), findsNothing);
      await tester.tap(dictionaryPickerOption('Ăn uống'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-search')),
        'Uống',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(service.lastCategory, 'Ăn uống');
      expect(service.lastSort, 'word_desc');
      expect(service.lastSearch, 'Uống');
      expect(service.categoryLoads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      state.dispose();
    },
  );
  testWidgets(
    'dictionary resets a selected topic removed by an administrator',
    (tester) async {
      final auth = await authenticatedProvider();
      final state = AppState(),
          service = ChangingDictionaryCategories()..multiPage = true;
      await tester.pumpWidget(dictionaryHarness(auth, state, service));
      await tester.pumpAndSettle();
      await openDictionaryPicker(tester, 'Sắp xếp');
      await tester.tap(dictionaryPickerOption('Tên: Z–A'));
      await tester.pumpAndSettle();
      await openDictionaryPicker(tester, 'Chủ đề');
      await tester.tap(dictionaryPickerOption('Ăn uống'));
      await tester.pumpAndSettle();
      expect(service.lastCategory, 'Ăn uống');
      await tester.ensureVisible(find.byTooltip('Trang sau'));
      await tester.tap(find.byTooltip('Trang sau'));
      await tester.pumpAndSettle();
      expect(service.lastPage, 2);

      service.archived = true;
      final refresh = find.widgetWithText(TextButton, 'Làm mới');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(service.lastCategory, isNull);
      expect(service.lastPage, 1);
      expect(service.lastSort, 'word_desc');
      expect(service.categoryLoads, 2);
      expect(find.text('Tất cả chủ đề'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Ăn uống'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GridView),
          matching: find.text('Xin chào'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      state.dispose();
    },
  );
  testWidgets(
    'dictionary topic selector filters the server catalog on phone layout',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      final state = AppState();
      await tester.pumpWidget(
        dictionaryHarness(auth, state, DemoDictionaryService()),
      );
      await tester.pumpAndSettle();
      await openDictionaryPicker(tester, 'Chủ đề');
      await tester.tap(dictionaryPickerOption('Ăn uống'));
      await tester.pumpAndSettle();
      expect(find.text('Xin chào'), findsNothing);
      expect(
        find.descendant(of: find.byType(GridView), matching: find.text('Uống')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-search')),
        'Uống',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Ăn'), findsNothing);
      expect(
        find.descendant(of: find.byType(GridView), matching: find.text('Uống')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      state.dispose();
    },
  );
  test('lưu và xóa đúng hội thoại được chọn', () {
    final state = AppState();
    state.saveConversation('Hội thoại trước', ConversationDirection.text);
    state.saveConversation(
      'Một hội thoại mới',
      ConversationDirection.speechToText,
    );
    final added = state.selectedConversation!;
    expect(added.content, 'Một hội thoại mới');
    state.selectConversation(state.history.last);
    expect(state.selectedConversation!.id, isNot(added.id));
    state.removeConversation(added.id);
    expect(state.history.any((h) => h.id == added.id), isFalse);
    state.dispose();
  });

  test('yêu thích được bật/tắt và xóa dữ liệu demo có hiệu lực', () {
    final state = AppState();
    state.toggleSign('Giúp đỡ');
    expect(state.favorites, contains('Giúp đỡ'));
    state.toggleSign('Giúp đỡ');
    expect(state.favorites, isNot(contains('Giúp đỡ')));
    state.addWord('Xin chào');
    state.clearLocalData();
    expect(state.history, isEmpty);
    expect(state.favorites, isEmpty);
    expect(state.sentence, isEmpty);
    state.dispose();
  });

  for (final id in screenNames.keys) {
    testWidgets('$id dựng được ở kích thước điện thoại', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = await authenticatedProvider();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        SignVoiceApp(
          initialScreen: id,
          auth: auth,
          state: AppState(),
          adminService: DemoDictionaryService(),
          learningService: DemoLearningService(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      // Dọn timer và animation trước khi kết thúc từng test.
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('form đăng nhập chặn email sai và mật khẩu ngắn', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthProvider(authService: FakeAuthService());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        initialScreen: 'S05',
        auth: auth,
        state: AppState(),
        adminService: DemoDictionaryService(),
        learningService: DemoLearningService(),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'sai-email');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    final login = find.widgetWithText(FilledButton, 'Đăng nhập');
    await tester.ensureVisible(login);
    await tester.tap(login);
    await tester.pump();
    expect(find.text('Email không đúng định dạng.'), findsOneWidget);
    expect(find.text('Mật khẩu cần ít nhất 8 ký tự.'), findsOneWidget);
  });

  testWidgets('dùng thử mở trang chủ và điều hướng từ điển', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthProvider(authService: FakeAuthService());
    await tester.pumpWidget(
      SignVoiceApp(
        initialScreen: 'S05',
        auth: auth,
        state: AppState(),
        adminService: DemoDictionaryService(),
        learningService: DemoLearningService(),
      ),
    );
    final guest = find.text('Dùng thử không cần tài khoản');
    await tester.ensureVisible(guest);
    await tester.tap(guest);
    await tester.pumpAndSettle();
    expect(find.text('Dùng thử SignVoice trong 10 phút'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(auth.isAuthenticated, isFalse);
    await tester.tap(guest);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vào dùng thử'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('Từ điển'));
    await tester.pumpAndSettle();
    expect(find.text('Khám phá ký hiệu'), findsOneWidget);
    expect(find.text('Khám phá'), findsOneWidget);
    expect(find.text('Chào hỏi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });

  testWidgets('mở đúng mục từ điển được chọn', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        initialScreen: 'S22',
        auth: auth,
        state: AppState(),
        adminService: DemoDictionaryService(),
        learningService: DemoLearningService(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chào hỏi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cảm ơn'));
    await tester.pumpAndSettle();
    expect(find.byType(LearningWordContent), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LearningWordContent),
        matching: find.text('Bày tỏ sự biết ơn.'),
      ),
      findsOneWidget,
    );
  });
}
