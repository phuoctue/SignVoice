import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/services/notifications/push_notice.dart';

void main() {
  final now = DateTime.utc(2026, 10, 25);
  final payload = <String, dynamic>{
    'userId': 'a' * 24,
    'notificationId': 'b' * 24,
    'title': 'Ôn tập',
    'body': 'Đến giờ học',
    'route': '/learn?tab=1',
    'expiresAt': '${now.add(const Duration(days: 1)).millisecondsSinceEpoch}',
  };
  test('only the signed-in recipient can render a push', () {
    expect(pushNoticeFor(payload, 'a' * 24, now: now)?.title, 'Ôn tập');
    expect(pushNoticeFor(payload, null, now: now), isNull);
    expect(pushNoticeFor(payload, 'c' * 24, now: now), isNull);
    expect(
      pushNoticeFor({...payload, 'userId': null}, 'a' * 24, now: now),
      isNull,
    );
  });
  test('expired or malformed payloads never render', () {
    expect(
      pushNoticeFor(payload, 'a' * 24, now: now.add(const Duration(days: 2))),
      isNull,
    );
    expect(
      pushNoticeFor(
        {...payload, 'route': 'https://example.org'},
        'a' * 24,
        now: now,
      ),
      isNull,
    );
    expect(
      pushNoticeFor({...payload, 'notificationId': ''}, 'a' * 24, now: now),
      isNull,
    );
  });
}
