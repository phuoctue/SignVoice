import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/notifications/notification_service.dart';
import 'package:sign_voice/services/user/user_data_service.dart';

import 'auth_fixtures.dart';
import 'user_data_integration_test.dart' show UserDataFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timezone = MethodChannel('flutter_timezone');
  final calls = <MethodCall>[];
  var allowed = true;
  var exact = true;
  final installed = <int, Map<String, dynamic>>{};
  setUp(() {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    allowed = true;
    exact = true;
    installed.clear();
    SharedPreferences.setMockInitialValues({
      'notification_owner': testUser().id,
    });
    messenger.setMockMethodCallHandler(
      timezone,
      (_) async => 'Asia/Ho_Chi_Minh',
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'zonedSchedule') {
        installed[call.arguments['id'] as int] = Map<String, dynamic>.from(
          call.arguments as Map,
        );
      }
      if (call.method == 'cancel') installed.remove(call.arguments['id']);
      if (call.method == 'cancelAll' ||
          call.method == 'cancelAllPendingNotifications') {
        installed.clear();
      }
      if (call.method == 'pendingNotificationRequests') {
        return installed.entries
            .map(
              (entry) => {
                'id': entry.key,
                'title': entry.value['title'],
                'body': entry.value['body'],
                'payload': entry.value['payload'],
              },
            )
            .toList();
      }
      return switch (call.method) {
        'initialize' => true,
        'canScheduleExactNotifications' => exact,
        'areNotificationsEnabled' ||
        'requestNotificationsPermission' => allowed,
        _ => null,
      };
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(timezone, null);
  });
  test(
    'installs only selected weekdays and cancels alarms at logout',
    () async {
      final fixture = UserDataFixture();
      fixture.settings['studyReminder'] = {
        'enabled': true,
        'hour': 19,
        'minute': 30,
        'weekdays': [1, 5],
        'timezone': 'Asia/Ho_Chi_Minh',
      };
      final state = AppState(service: fixture.service)
        ..bindAccount(testUser().id, asGuest: false);
      final service = NotificationService(state, onOpen: (_) {});
      addTearDown(() {
        service.dispose();
        state.dispose();
      });
      await state.synchronize();
      await service.retry();
      final scheduled = calls
          .where((call) => call.method == 'zonedSchedule')
          .toList();
      expect(scheduled.map((call) => call.arguments['id']), [7101, 7105]);
      expect(
        scheduled.every(
          (call) =>
              call.arguments['scheduledDateTime'].toString().contains('19:30'),
        ),
        true,
      );
      calls.clear();
      state.unbindAccount();
      await service.retry();
      expect(calls.where((call) => call.method == 'cancelAll'), isNotEmpty);
      expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    },
  );
  test('keeps existing alarms while the same account is not ready offline', () async {
    // The already stored OS alarms must survive startup until settings arrive.
    // Holding synchronize lets this exercise the exact not-ready state.
    final held = AppState(service: _UnavailableUserData())
      ..bindAccount(testUser().id, asGuest: false);
    final offline = NotificationService(held, onOpen: (_) {});
    addTearDown(() {
      offline.dispose();
      held.dispose();
    });
    await offline.retry();
    expect(
      calls.where(
        (call) =>
            call.method == 'cancelAll' ||
            call.method == 'cancelAllPendingNotifications',
      ),
      isEmpty,
    );
  });
  test('denied permission does not install any reminders', () async {
    allowed = false;
    final fixture = UserDataFixture();
    fixture.settings['studyReminder'] = {
      'enabled': true,
      'hour': 19,
      'minute': 30,
      'weekdays': [1],
      'timezone': 'Asia/Ho_Chi_Minh',
    };
    final state = AppState(service: fixture.service)
      ..bindAccount(testUser().id, asGuest: false);
    final service = NotificationService(state, onOpen: (_) {});
    addTearDown(() {
      service.dispose();
      state.dispose();
    });
    await state.synchronize();
    expect(await service.requestPermission(), false);
    await service.retry();
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
  });
  test('resuming preserves a pending inexact alarm instead of pushing it to next week', () async {
    exact = false;
    final fixture = UserDataFixture();
    fixture.settings['studyReminder'] = {
      'enabled': true,
      'hour': 13,
      'minute': 58,
      'weekdays': [1],
      'timezone': 'Asia/Ho_Chi_Minh',
    };
    final state = AppState(service: fixture.service)
      ..bindAccount(testUser().id, asGuest: false);
    final service = NotificationService(state, onOpen: (_) {});
    addTearDown(() {
      service.dispose();
      state.dispose();
    });
    await state.synchronize();
    await service.retry();
    expect(installed.keys, [7101]);
    expect(service.scheduledReminderCount, 1);
    calls.clear();
    await service.retry();
    expect(
      calls.where(
        (call) => [
          'zonedSchedule',
          'cancel',
          'cancelAllPendingNotifications',
        ].contains(call.method),
      ),
      isEmpty,
    );
    expect(installed.keys, [7101]);
    // Recreating the service (app restart) must retain the OS plan too.
    final reopened = NotificationService(state, onOpen: (_) {});
    addTearDown(reopened.dispose);
    await reopened.retry();
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
  });
  test(
    'one-minute check uses Android scheduling and survives routine resync',
    () async {
      final fixture = UserDataFixture();
      final state = AppState(service: fixture.service)
        ..bindAccount(testUser().id, asGuest: false);
      final service = NotificationService(state, onOpen: (_) {});
      addTearDown(() {
        service.dispose();
        state.dispose();
      });
      await state.synchronize();
      await service.testScheduledReminder();
      expect(installed.containsKey(7098), isTrue);
      await service.retry();
      expect(installed.containsKey(7098), isTrue);
    },
  );
}

class _UnavailableUserData extends UserDataService {
  @override
  Future<UserRecord> profile() async => throw StateError('Offline');
  @override
  Future<UserRecord> settings() async => {};
  @override
  Future<UserRecord> conversations({
    int page = 1,
    int limit = 20,
    String search = '',
    String? direction,
    bool? favorite,
  }) async => {'items': [], 'pages': 1};
  @override
  Future<List<UserRecord>> favorites() async => [];
}
