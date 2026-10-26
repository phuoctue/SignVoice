import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_notice.dart';

Future<void> showPushNotice(
  FlutterLocalNotificationsPlugin plugin,
  PushNotice notice,
) => plugin.show(
  id: notice.id,
  title: notice.title,
  body: notice.body,
  notificationDetails: NotificationDetails(
    android: AndroidNotificationDetails(
      'signvoice_updates',
      'Thông báo SignVoice',
      icon: 'ic_stat_study',
      tag: notice.notificationId,
    ),
  ),
  payload: notice.route,
);

/// Rejects notifications for an old account after logout, including messages
/// already queued by FCM while the device was offline.
@pragma('vm:entry-point')
Future<void> handleBackgroundPush(RemoteMessage message) async {
  await Firebase.initializeApp();
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  final owner = preferences.getString('notification_owner');
  final notice = pushNoticeFor(message.data, owner);
  if (notice == null) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_study'),
    ),
  );
  final android = plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (await android?.areNotificationsEnabled() != true) return;
  await preferences.reload();
  if (preferences.getString('notification_owner') != owner) return;
  await showPushNotice(plugin, notice);
}
