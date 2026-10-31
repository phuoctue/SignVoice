import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/notifications/notification_service.dart';
import 'package:sign_voice/widgets/notification_bell.dart';

import 'auth_fixtures.dart';
import 'user_data_integration_test.dart' show UserDataFixture, ok;

class InboxFixture extends UserDataFixture {
  bool due = false, read = false;
  int calls = 0;
  Completer<http.Response>? pending;
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/users/notifications')) {
      calls++;
      if (pending != null) return pending!.future;
      return ok({
        'items': [
          if (due)
            {
              '_id': 'reminder',
              'kind': 'STUDY_REMINDER',
              'title': 'Đến giờ học rồi!',
              'body': 'Lịch học lúc 19:30',
              'read': read,
            },
        ],
      });
    }
    if (request.url.path.endsWith('/users/notifications/reminder')) {
      read = true;
      return ok({'read': true});
    }
    return super.handle(request);
  }
}

void main() {
  testWidgets(
    'due schedule updates the bell and opens an inbox dialog on the current page',
    (tester) async {
      final fixture = InboxFixture();
      final state = AppState(service: fixture.service)
        ..bindAccount(testUser().id, asGuest: false);
      await state.synchronize();
      final service = NotificationService(state, onOpen: (_) {}, webInbox: true)
        ..start();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: service,
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [Text('Trang hiện tại'), NotificationBell()],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.unreadCount, 0);
      fixture.due = true;
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      // Widget clock advances the timer; force bypasses the wall-clock cache TTL.
      await service.loadInbox(force: true);
      await tester.pumpAndSettle();
      expect(service.unreadCount, 1);
      await tester.tap(find.byTooltip('Thông báo, 1 chưa đọc'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationInboxDialog), findsOneWidget);
      final panel = tester.getRect(find.byType(NotificationInboxDialog));
      expect(panel.width, lessThanOrEqualTo(420));
      expect(panel.left, greaterThanOrEqualTo(12));
      expect(
        panel.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(NotificationBell)).bottom,
        ),
      );
      final schedule = state.studyReminder.toJson();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(state.notificationsEnabled, false);
      expect(fixture.settings['notificationsEnabled'], false);
      expect(state.studyReminder.toJson(), schedule);
      expect(find.text('Trang hiện tại'), findsOneWidget);
      await tester.tap(find.text('Đến giờ học rồi!'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationInboxDialog), findsNothing);
      expect(service.unreadCount, 0);
      expect(fixture.read, true);
      expect(find.text('Trang hiện tại'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      state.dispose();
      fixture.api.dispose();
    },
  );

  test('a late inbox response cannot cross account boundaries', () async {
    final fixture = InboxFixture();
    final state = AppState(service: fixture.service)
      ..bindAccount(testUser().id, asGuest: false);
    await state.synchronize();
    fixture.pending = Completer<http.Response>();
    final service = NotificationService(state, onOpen: (_) {}, webInbox: true)
      ..start();
    final loading = service.loadInbox(force: true);
    state.unbindAccount();
    fixture.pending!.complete(
      ok({
        'items': [
          {'_id': 'private', 'read': false},
        ],
      }),
    );
    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(service.inbox, isEmpty);
    expect(service.unreadCount, 0);
    service.dispose();
    state.dispose();
    fixture.api.dispose();
  });
}
