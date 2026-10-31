import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:sign_voice/services/notifications/study_reminder.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test(
    'next reminder skips a time already reached and preserves local hour',
    () {
      final zone = tz.getLocation('Asia/Ho_Chi_Minh');
      const reminder = StudyReminder(
        enabled: true,
        hour: 19,
        minute: 30,
        weekdays: [1, 5],
      );
      expect(
        reminder.nextForDay(1, tz.TZDateTime(zone, 2026, 10, 26, 19, 30)),
        tz.TZDateTime(zone, 2026, 11, 2, 19, 30),
      );
      expect(
        reminder.nextForDay(5, tz.TZDateTime(zone, 2026, 10, 26, 20)),
        tz.TZDateTime(zone, 2026, 10, 30, 19, 30),
      );
    },
  );
  test('weekly reminder keeps wall time across daylight saving change', () {
    final zone = tz.getLocation('America/New_York');
    const reminder = StudyReminder(
      enabled: true,
      hour: 8,
      minute: 15,
      weekdays: [7],
    );
    final result = reminder.nextForDay(
      7,
      tz.TZDateTime(zone, 2026, 10, 31, 12),
    );
    expect(result.hour, 8);
    expect(result.timeZoneOffset, const Duration(hours: -5));
  });
}
