import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/notifications/notification_screens.dart';
import 'package:sign_voice/services/notifications/notification_service.dart';
import 'package:sign_voice/services/notifications/study_reminder.dart';

class DeviceSchedule extends NotificationService {
  DeviceSchedule(super.state) : super(onOpen: (_) {}) {
    permissionGranted = exact = true;
    scheduledReminderCount = 1;
    final today = DateTime.now();
    nextReminder = DateTime(today.year, today.month, today.day + 7);
  }
  @override
  bool get supported => true;
  int tests = 0;
  @override
  Future<void> testScheduledReminder() async {
    tests++;
  }
}

void main() {
  testWidgets(
    'mobile reminder keeps save visible and separates support from schedule',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState()
        ..studyReminder = StudyReminder(
          enabled: true,
          hour: 0,
          minute: 0,
          weekdays: [DateTime.now().weekday],
        );
      final device = DeviceSchedule(state);
      addTearDown(device.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<NotificationService>.value(
          value: device,
          child: AppScope(
            state: state,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
              home: const StudyReminderScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final save = find.text('Lưu cài đặt');
      expect(tester.getRect(save).bottom, lessThan(800));
      expect(save.hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Lần nhắc tiếp theo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Giờ nhắc hôm nay đã qua'), findsOneWidget);
      expect(find.text('Pin và hoạt động nền'), findsNothing);
      await tester.ensureVisible(find.text('Thử nhắc sau 1 phút'));
      await tester.tap(find.text('Thử nhắc sau 1 phút'));
      await tester.pumpAndSettle();
      expect(device.tests, 1);
      expect(state.studyReminder.hour, 0);
      expect(device.scheduledReminderCount, 1);
      // A confirmation must not cover the persistent save action.
      expect(save.hitTestable(), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Quyền & hỗ trợ'));
      await tester.tap(find.text('Quyền & hỗ trợ'));
      await tester.pumpAndSettle();
      expect(find.text('Pin và hoạt động nền'), findsOneWidget);
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Lặp lại vào'));
      await tester.pumpAndSettle();
      final day = DateTime.now().weekday == 1 ? 'T3' : 'T2';
      await tester.tap(find.widgetWithText(FilterChip, day));
      await tester.pumpAndSettle();
      expect(find.textContaining('Bạn có thay đổi chưa lưu'), findsOneWidget);
      expect(find.text('Lần nhắc tiếp theo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
