import 'package:timezone/timezone.dart' as tz;

class StudyReminder {
  const StudyReminder({
    this.enabled = false,
    this.hour = 19,
    this.minute = 0,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.timezone = 'Asia/Ho_Chi_Minh',
  });
  final bool enabled;
  final int hour, minute;
  final List<int> weekdays;
  final String timezone;
  factory StudyReminder.fromJson(Map<String, dynamic>? data) => StudyReminder(
    enabled: data?['enabled'] == true,
    hour: (data?['hour'] as num?)?.toInt() ?? 19,
    minute: (data?['minute'] as num?)?.toInt() ?? 0,
    weekdays: (data?['weekdays'] as List? ?? [1, 2, 3, 4, 5, 6, 7]).cast<int>(),
    timezone: data?['timezone'] as String? ?? 'Asia/Ho_Chi_Minh',
  );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays,
    'timezone': timezone,
  };
  tz.TZDateTime nextForDay(int weekday, tz.TZDateTime now) {
    var date = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    final offset = (weekday - now.weekday + 7) % 7;
    date = tz.TZDateTime(
      now.location,
      date.year,
      date.month,
      date.day + offset,
      hour,
      minute,
    );
    if (!date.isAfter(now)) {
      date = tz.TZDateTime(
        now.location,
        date.year,
        date.month,
        date.day + 7,
        hour,
        minute,
      );
    }
    return date;
  }
}
