import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/core/theme.dart';
import 'package:sign_voice/screens/admin/admin_ui.dart';

Future<void> pickerApp(
  WidgetTester tester, {
  Size size = const Size(375, 812),
  bool dark = false,
  double scale = 1,
  Map<String, String> options = const {'ALL': 'Tất cả', 'ACTIVE': 'Hoạt động'},
  bool enabled = true,
  ValueChanged<String>? onChanged,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: makeTheme(dark: dark, highContrast: false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                AdminSelectField(
                  label: 'Trạng thái',
                  value: 'ALL',
                  options: options,
                  onChanged: enabled ? onChanged ?? (_) {} : null,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'floating label paints its upper half without clipping at $scale',
      (tester) async {
        final boundary = GlobalKey();
        const labelColor = Color(0xFFFF00FF);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              inputDecorationTheme: const InputDecorationTheme(
                border: OutlineInputBorder(),
                floatingLabelStyle: TextStyle(color: labelColor, fontSize: 16),
              ),
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        AdminSelectField(
                          label: 'Trạng thái',
                          value: 'ALL',
                          options: const {'ALL': 'Tất cả'},
                          onChanged: (_) {},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = tester.getRect(find.text('Trạng thái'));
        final render = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundary),
        );
        final origin = render.localToGlobal(Offset.zero);
        var visible = 0;
        await tester.runAsync(() async {
          final shot = await render.toImage();
          final pixels = await shot.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final area = label.shift(-origin);
          for (
            var y = area.top.ceil();
            y < (area.top + area.height * .4).floor();
            y++
          ) {
            for (var x = area.left.ceil(); x < area.right.floor(); x++) {
              final offset = (y * shot.width + x) * 4;
              if (pixels!.getUint8(offset) > 200 &&
                  pixels.getUint8(offset + 1) < 100 &&
                  pixels.getUint8(offset + 2) > 200) {
                visible++;
              }
            }
          }
          shot.dispose();
        });
        expect(
          visible,
          greaterThan(5),
          reason: 'The top of the floating label must remain painted outside the outline.',
        );
      },
    );
  }

  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 640),
      const Size(844, 390),
      const Size(800, 1024),
    ]) {
      testWidgets(
        'picker fits $size with large text and reduced motion dark=$dark',
        (tester) async {
          String? selected;
          await pickerApp(
            tester,
            size: size,
            dark: dark,
            scale: 2,
            options: const {
              'ALL': 'Tất cả',
              'OPEN': 'Có báo cáo chưa xử lý',
              'REVIEW': 'Chờ kiểm tra lại',
              'HIDDEN': 'Ẩn khỏi khám phá',
              'BLOCKED': 'Chặn chia sẻ',
            },
            onChanged: (value) => selected = value,
          );
          await tester.tap(find.byType(AdminSelectField));
          await tester.pumpAndSettle();
          final dialog = tester.getRect(
            find.byKey(const ValueKey('admin-choice-menu')),
          );
          expect(dialog.left, greaterThanOrEqualTo(20));
          expect(dialog.right, lessThanOrEqualTo(size.width - 20));
          expect(dialog.height, lessThanOrEqualTo(520));
          expect(dialog.top, greaterThanOrEqualTo(tester.getRect(find.byType(AdminSelectField)).bottom));
          expect(dialog.bottom, lessThan(size.height));
          expect(find.byIcon(Icons.check_circle), findsOneWidget);
          await tester.tap(find.byTooltip('Đóng lựa chọn'));
          await tester.pumpAndSettle();
          expect(selected, isNull);
          expect(find.byType(Dialog), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'long category picker searches, survives keyboard and returns id',
    (tester) async {
      String? selected;
      await pickerApp(
        tester,
        size: const Size(375, 812),
        scale: 2,
        options: {
          'ALL': 'Tất cả',
          for (var i = 0; i < 20; i++) 'c$i': 'Danh mục $i',
          'health': 'Cơ thể và sức khỏe',
        },
        onChanged: (value) => selected = value,
      );
      await tester.tap(find.byType(AdminSelectField));
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Tìm trong danh sách');
      await tester.enterText(search, 'sức khỏe');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cơ thể và sức khỏe'));
      await tester.tap(find.text('Cơ thể và sức khỏe'));
      await tester.pumpAndSettle();
      expect(selected, 'health');
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled picker ignores tap; escape dismisses without choosing',
    (tester) async {
      await pickerApp(tester, enabled: false);
      await tester.tap(find.byType(AdminSelectField));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await pickerApp(tester);
      await tester.tap(find.byType(AdminSelectField));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets('field follows external reset and validates missing selection', (
    tester,
  ) async {
    final key = GlobalKey<FormState>();
    String? value;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return Form(
                key: key,
                child: AdminSelectField(
                  label: 'Role',
                  value: value,
                  options: const {'USER': 'Người dùng', 'STAFF': 'Nhân viên'},
                  onChanged: (next) => set(() => value = next),
                  validator: (value) =>
                      value == null ? 'Vui lòng chọn role.' : null,
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Vui lòng chọn role.'), findsOneWidget);
    update(() => value = 'STAFF');
    await tester.pump();
    expect(find.text('Nhân viên'), findsOneWidget);
    expect(key.currentState!.validate(), isTrue);
  });

  testWidgets(
    'group selection respects allowed permissions and preserves other groups',
    (tester) async {
      var selected = <String>{'dictionary:read', 'staff:access'};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, set) => AdminPermissionPicker(
                  selected: selected,
                  allowed: const {'staff:access'},
                  onChanged: (next) => set(() => selected = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Bỏ chọn nhóm'));
      await tester.pumpAndSettle();
      expect(selected, {'dictionary:read'});
      await tester.tap(find.text('Chọn nhóm'));
      await tester.pumpAndSettle();
      expect(selected, {'dictionary:read', 'staff:access'});
      final admin = tester.widget<CheckboxListTile>(
        find.widgetWithText(
          CheckboxListTile,
          'Quản trị tài khoản, role và phiên đăng nhập (ADMIN)',
        ),
      );
      expect(admin.onChanged, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
