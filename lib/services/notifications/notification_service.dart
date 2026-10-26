import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/app_state.dart';
import 'notification_background.dart';
import 'push_notice.dart';

/// Coordinates one device with the current account. Operations are serialized so
/// a late save or login cannot leave the previous account's alarms installed.
class NotificationService extends ChangeNotifier {
  NotificationService(this.state, {required this.onOpen});
  final AppState state;
  final void Function(String route) onOpen;
  final _local = FlutterLocalNotificationsPlugin();
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool permissionGranted = false, exact = false, pushReady = false;
  int inboxRevision = 0;
  void refreshInbox() {
    inboxRevision++;
    _notify();
  }

  String? error;
  String timezone = 'Asia/Ho_Chi_Minh';
  Future<void>? _initializing;
  Future<void> _queue = Future.value();
  Future<void> _ownerWrites = Future.value();
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _messages, _opened;
  String? _signature, _owner;
  int _generation = 0;
  bool _disposed = false;
  void start() {
    state.addListener(refresh);
    refresh();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _open(String? route) {
    // Remote payloads can only open existing learning destinations.
    if (route == '/learn' ||
        route == '/learn?tab=1' ||
        route == '/notifications') {
      onOpen(route!);
    }
  }

  Future<void> initialize() =>
      _initializing ??= _initialize().catchError((Object e) {
        _initializing = null;
        throw e;
      });
  Future<void> _initialize() async {
    if (!supported) return;
    tzdata.initializeTimeZones();
    timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    tz.setLocalLocation(tz.getLocation(timezone));
    _owner = (await SharedPreferences.getInstance()).getString(
      'notification_owner',
    );
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_study'),
      ),
      onDidReceiveNotificationResponse: (response) => _open(response.payload),
    );
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'signvoice_updates',
        'Thông báo SignVoice',
        description: 'Từ mới và ôn tập ký hiệu',
        importance: Importance.defaultImportance,
      ),
    );
    permissionGranted = await android.areNotificationsEnabled() ?? false;
    exact = await android.canScheduleExactNotifications() ?? false;
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _open(launch?.notificationResponse?.payload);
    }
    await _initializePush();
    _notify();
  }

  Future<void> _initializePush() async {
    try {
      await Firebase.initializeApp();
      // HTTP v1 targets registration tokens. Keep the compatible token API
      // until the server moves to the separate FID delivery API.
      // ignore: deprecated_member_use
      _tokens = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (state.ready &&
            !state.guest &&
            state.notificationsEnabled &&
            permissionGranted) {
          try {
            await state.service?.registerNotificationDevice(token, 'android');
          } catch (_) {
            error = 'Chưa đăng ký được push. Hãy thử lại khi có mạng.';
            _notify();
          }
        }
      });
      _messages = FirebaseMessaging.onMessage.listen((message) {
        refreshInbox();
        final notice = pushNoticeFor(message.data, state.accountId);
        if (notice != null &&
            state.ready &&
            !state.guest &&
            state.accountId != null &&
            permissionGranted &&
            state.notificationsEnabled &&
            _owner == state.accountId) {
          unawaited(
            showPushNotice(_local, notice).catchError((Object _) {
              error = 'Chưa hiện được thông báo. Kiểm tra quyền của ứng dụng.';
              _notify();
            }),
          );
        }
      });
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _open(message.data['route'] as String?),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _open(initial.data['route'] as String?);
      pushReady = true;
    } catch (_) {
      await _tokens?.cancel();
      await _messages?.cancel();
      await _opened?.cancel();
      pushReady = false;
      error =
          'Chưa khởi tạo được push Firebase. Nhắc học trên máy vẫn dùng được.';
    }
  }

  Future<bool> requestPermission({bool exactAlarm = false}) async {
    if (!supported) return false;
    await initialize();
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()!;
    permissionGranted = await android.requestNotificationsPermission() ?? false;
    if (permissionGranted &&
        exactAlarm &&
        !(await android.canScheduleExactNotifications() ?? false)) {
      await android.requestExactAlarmsPermission();
    }
    exact = await android.canScheduleExactNotifications() ?? false;
    _notify();
    return permissionGranted;
  }

  void refresh() {
    if (!supported || !state.persisted || _disposed) return;
    final signature =
        '${state.accountId}:${state.ready}:${state.guest}:${state.notificationsEnabled}:${jsonEncode(state.studyReminder.toJson())}';
    if (signature == _signature) return;
    _signature = signature;
    final generation = ++_generation;
    final activeOwner = state.notificationsEnabled && !state.guest
        ? state.accountId
        : null;
    // Persist ownership independently of network operations so a background
    // message cannot display for an account that just logged out offline.
    _ownerWrites = _ownerWrites
        .then((_) async {
          final preferences = await SharedPreferences.getInstance();
          final previous = preferences.getString('notification_owner');
          if (activeOwner == null) {
            await preferences.remove('notification_owner');
          } else {
            await preferences.setString('notification_owner', activeOwner);
          }
          if (previous != activeOwner) await _local.cancelAll();
        })
        .catchError((Object _) {
          error = 'Chưa cập nhật được thông báo trên thiết bị.';
        });
    _queue = _queue.then((_) async {
      if (generation != _generation || _disposed) return;
      try {
        await _ownerWrites;
        await initialize();
        if (generation != _generation || _disposed) return;
        if (_owner != state.accountId ||
            !state.notificationsEnabled ||
            state.guest) {
          await _local.cancelAll();
          if (pushReady) {
            await FirebaseMessaging.instance.setAutoInitEnabled(false);
            // ignore: deprecated_member_use
            await FirebaseMessaging.instance.deleteToken();
          }
        }
        _owner = state.accountId;
        if (!state.ready ||
            state.accountId == null ||
            state.guest ||
            !state.notificationsEnabled) {
          return;
        }
        timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
        tz.setLocalLocation(tz.getLocation(timezone));
        // Keep the existing OS alarms while account data is loading/offline.
        await _local.cancelAllPendingNotifications();
        final android = _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!;
        permissionGranted = await android.areNotificationsEnabled() ?? false;
        exact = await android.canScheduleExactNotifications() ?? false;
        if (!permissionGranted) return;
        final reminder = state.studyReminder;
        if (reminder.enabled) {
          // Follow the current device timezone when the user travels.
          for (final weekday in reminder.weekdays) {
            if (generation != _generation || _disposed) return;
            await _local.zonedSchedule(
              id: 7100 + weekday,
              title: 'Đến giờ học ký hiệu',
              body: 'Dành vài phút học và ôn lại ký hiệu cùng SignVoice nhé.',
              scheduledDate: reminder.nextForDay(
                weekday,
                tz.TZDateTime.now(tz.local),
              ),
              notificationDetails: const NotificationDetails(
                android: AndroidNotificationDetails(
                  'signvoice_study',
                  'Nhắc học',
                  channelDescription: 'Lịch học do bạn lựa chọn',
                  icon: 'ic_stat_study',
                  importance: Importance.high,
                ),
              ),
              androidScheduleMode: exact
                  ? AndroidScheduleMode.exactAllowWhileIdle
                  : AndroidScheduleMode.inexactAllowWhileIdle,
              matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
              payload: '/learn?tab=1',
            );
          }
        }
        if (pushReady && generation == _generation) {
          await FirebaseMessaging.instance.setAutoInitEnabled(true);
          // ignore: deprecated_member_use
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null && generation == _generation) {
            await state.service!.registerNotificationDevice(token, 'android');
          }
        }
      } catch (_) {
        error = 'Chưa đồng bộ được thông báo trên máy này. Kiểm tra mạng và thử lại.';
      } finally {
        _notify();
      }
    });
  }

  Future<void> retry() async {
    error = null;
    if (supported && state.persisted && !_disposed) {
      try {
        await initialize();
        if (!pushReady) await _initializePush();
      } catch (_) {
        error = 'Chưa khởi tạo được thông báo trên máy này.';
      }
      _signature = null;
      refresh();
      await _queue;
    }
    _notify();
  }

  Future<void> testReminder() async {
    if (!await requestPermission()) {
      throw StateError('Hãy cho phép thông báo trong Cài đặt ứng dụng.');
    }
    await _local.show(
      id: 7099,
      title: 'Nhắc học SignVoice',
      body: 'Thông báo trên thiết bị đã hoạt động. Cùng học ký hiệu nhé!',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'signvoice_study',
          'Nhắc học',
          icon: 'ic_stat_study',
          importance: Importance.high,
        ),
      ),
      payload: '/learn?tab=1',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    state.removeListener(refresh);
    _tokens?.cancel();
    _messages?.cancel();
    _opened?.cancel();
    super.dispose();
  }
}
