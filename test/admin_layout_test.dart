import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/screens/admin/admin_management_screens.dart';
import 'package:sign_voice/screens/admin/admin_ui.dart';

import 'admin_workspace_test.dart' show pumpApp;

void main() {
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 640), const Size(844, 390)]) {
      for (final resource in ['users', 'roles', 'dictionary', 'categories']) {
        testWidgets(
          '$resource editor fits $size with keyboard and 2x text dark=$dark',
          (tester) async {
            await pumpApp(tester, screen: '/admin/$resource');
            await tester.tap(find.text('Thêm mới'));
            await tester.pumpAndSettle();
            final state = AppScope.of(
              tester.element(find.byType(AdminEditorScreen)),
            );
            state.update(() {
              state.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
              state.fontScale = 2;
            });
            tester.view.physicalSize = size;
            tester.view.viewInsets = const FakeViewPadding(bottom: 180);
            addTearDown(tester.view.resetViewInsets);
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
            await tester.pumpAndSettle();
            final save = find.widgetWithText(FilledButton, 'Lưu thay đổi');
            final rect = tester.getRect(save);
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.bottom, lessThanOrEqualTo(size.height - 180));
            if (resource == 'roles') {
              final group = find.text('Bộ sưu tập công khai');
              await Scrollable.ensureVisible(
                tester.element(group),
                alignment: .2,
              );
              await tester.pumpAndSettle();
              await tester.tap(group);
              await tester.pumpAndSettle();
            } else {
              final picker = find.byType(AdminSelectField).last;
              await Scrollable.ensureVisible(
                tester.element(picker),
                alignment: .2,
              );
              await tester.pumpAndSettle();
              await tester.tap(picker);
              await tester.pumpAndSettle();
              expect(find.byKey(const ValueKey('admin-choice-menu')), findsOneWidget);
              await tester.tap(find.byTooltip('Đóng lựa chọn'));
              await tester.pumpAndSettle();
            }
            // Submitting from below the fold must bring the first error into view.
            await tester.tap(save);
            await tester.pumpAndSettle();
            expect(find.textContaining('Cần ít nhất').evaluate(), isNotEmpty);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
