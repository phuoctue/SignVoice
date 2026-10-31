import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/app_state.dart';
import '../platform/page_visibility.dart';
import 'notification_background.dart';
import 'push_notice.dart';

/// Coordinates one device with the current account. Operations are serialized so
/// a late save or login cannot leave the previous account's alarms installed.
class NotificationService extends ChangeNotifier {
  NotificationService(
    this.state, {
    required this.onOpen,
    this.webInbox = kIsWeb,
  });
  final bool webInbox;
  List<Map<String, dynamic>> inbox = [];
  bool inboxLoading = false;
  String? inboxError;
  int get unreadCount => inbox.where((item) => item['read'] != true).length;
  Timer? _inboxTimer;
  void Function()? _cancelVisibility;
  DateTime? _inboxLoadedAt;
  int _inboxGeneration = 0;
  String? _inboxOwner, _inboxPlan;
  final AppState state;
  final void Function(String route) onOpen;
  final _local = FlutterLocalNotificationsPlugin();
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool permissionGranted = false, exact = false, pushReady = false;
  int scheduledReminderCount = 0;
  DateTime? nextReminder;
  bool reminderChannelBlocked = false;
  String? pushError;
  static const _settings = MethodChannel('signvoice/notifications');
  int inboxRevision = 0;
  void refreshInbox() {
    inboxRevision++;
    _notify();
  }

  String? error;
  String timezone = 'Asia/Ho_Chi_Minh';
  Future<void>? _initializing;
  Future<void> _queue = Future.value();
  Future<void> _pushQueue = Future.value();
  Future<void>? _pushInitializing;
  Future<void> _ownerWrites = Future.value();
  StreamSubscription<String>? _tokens;
  StreamSubscription<RemoteMessage>? _messages, _opened;
  String? _signature, _owner;
  int _generation = 0;
  bool _disposed = false;
  void start() {
    state.addListener(refresh);
    refresh();
    if (webInbox) {
      _inboxTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => loadInbox(),
      );
      _cancelVisibility = onPageVisible(() => loadInbox(force: true));
    }
  }

  Future<void> loadInbox({bool force = false}) async {
    if (_disposed ||
        !state.persisted ||
        !state.ready ||
        state.guest ||
        state.accountId == null ||
        inboxLoading) {
      return;
    }
    if (!force &&
        _inboxLoadedAt != null &&
        DateTime.now().difference(_inboxLoadedAt!) <
            const Duration(seconds: 25)) {
      return;
    }
    final epoch = state.accountEpoch, generation = ++_inboxGeneration;
    inboxLoading = true;
    inboxError = null;
    _notify();
    try {
      final result = await state.service!.notifications();
      if (_disposed ||
          generation != _inboxGeneration ||
          !state.isCurrent(epoch)) {
        return;
      }
      inbox = (result['items'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      _inboxLoadedAt = DateTime.now();
    } catch (_) {
      if (!_disposed &&
          generation == _inboxGeneration &&
          state.isCurrent(epoch)) {
        inboxError = 'Chưa tải được thông báo. Hãy thử lại.';
      }
    } finally {
      if (!_disposed && generation == _inboxGeneration) {
        inboxLoading = false;
        _notify();
      }
    }
  }

  Future<bool> markRead(Map<String, dynamic> item) async {
    final epoch = state.accountEpoch;
    try {
      await state.service?.readNotification('${item['_id']}');
      if (_disposed || !state.isCurrent(epoch)) return false;
      item['read'] = true;
      _notify();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _refreshWebInbox() {
    final owner = '${state.accountId}:${state.accountEpoch}';
    if (_inboxOwner != owner || state.guest || !state.ready) {
      _inboxOwner = owner;
      _inboxGeneration++;
      inbox = [];
      inboxLoading = false;
      inboxError = null;
      _inboxLoadedAt = null;
      _inboxPlan = null;
      _notify();
    }
    final plan = jsonEncode(state.studyReminder.toJson());
    final changed = _inboxPlan != plan;
    _inboxPlan = plan;
    unawaited(loadInbox(force: changed));
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
    _notify();
  }

  Future<void> openDeviceSettings({bool battery = false}) async {
    if (supported) {
      await _settings.invokeMethod<void>(
        battery ? 'openBatterySettings' : 'openNotificationSettings',
      );
    }
  }

  void _enqueuePush(int generation) {
    _pushQueue = _pushQueue
        .then((_) async {
          if (_disposed || generation != _generation || !state.ready) return;
          if (!pushReady) {
            final initializing = _pushInitializing ??= _initializePush();
            try {
              await initializing;
            } finally {
              _pushInitializing = null;
            }
          }
          if (_disposed || generation != _generation || !pushReady) return;
          if (state.guest ||
              state.accountId == null ||
              !state.notificationsEnabled ||
              !permissionGranted) {
            await FirebaseMessaging.instance.setAutoInitEnabled(false);
            // ignore: deprecated_member_use
            await FirebaseMessaging.instance.deleteToken().timeout(
              const Duration(seconds: 10),
            );
            return;
          }
          await FirebaseMessaging.instance.setAutoInitEnabled(true);
          // ignore: deprecated_member_use
          final token = await FirebaseMessaging.instance.getToken().timeout(
            const Duration(seconds: 10),
          );
          if (!_disposed && generation == _generation && token != null) {
            await state.service!.registerNotificationDevice(token, 'android');
            pushError = null;
          }
        })
        .catchError((Object _) {
          if (!_disposed && generation == _generation) {
            pushError = 'Chưa đăng ký được push. Nhắc học trên máy vẫn hoạt động độc lập.';
          }
        })
        .whenComplete(_notify);
  }

  Future<void> _initializePush() async {
    try {
      await Firebase.initializeApp();
      if (_disposed) return;
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
            pushError = 'Chưa đăng ký được push. Hãy thử lại khi có mạng.';
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
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 10));
      if (_disposed) {
        await _tokens?.cancel();
        await _messages?.cancel();
        await _opened?.cancel();
        return;
      }
      if (initial != null) _open(initial.data['route'] as String?);
      pushReady = true;
    } catch (_) {
      await _tokens?.cancel();
      await _messages?.cancel();
      await _opened?.cancel();
      pushReady = false;
      pushError =
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
    if (webInbox && !_disposed) _refreshWebInbox();
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
          scheduledReminderCount = 0;
          nextReminder = null;
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
        final android = _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!;
        permissionGranted = await android.areNotificationsEnabled() ?? false;
        exact = await android.canScheduleExactNotifications() ?? false;
        if (!permissionGranted) {
          scheduledReminderCount = 0;
          nextReminder = null;
          return;
        }
        try {
          final status = await _settings.invokeMapMethod<String, dynamic>(
            'status',
          );
          reminderChannelBlocked = status?['channelBlocked'] == true;
        } on MissingPluginException {
          /* Older Android host; permission UI still works. */
        }
        final reminder = state.studyReminder;
        final days = reminder.enabled ? reminder.weekdays.toSet() : <int>{};
        final plan = jsonEncode([
          state.accountId,
          reminder.toJson(),
          timezone,
          exact,
        ]);
        final preferences = await SharedPreferences.getInstance();
        final pending = await _local.pendingNotificationRequests();
        final installed = pending
            .where((item) => item.id >= 7101 && item.id <= 7107)
            .map((item) => item.id - 7100)
            .toSet();
        final unchanged =
            preferences.getString('signvoice_alarm_plan') == plan &&
            installed.length == days.length &&
            installed.containsAll(days);
        // Do not cancel an unchanged alarm on resume: an inexact alarm may still
        // be waiting for Android to deliver it after its requested minute.
        if (!unchanged) {
          // Follow the current device timezone when the user travels.
          for (final weekday in days) {
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
          for (var weekday = 1; weekday <= 7; weekday++) {
            if (!days.contains(weekday)) {
              await _local.cancel(id: 7100 + weekday);
            }
          }
          final actual = (await _local.pendingNotificationRequests())
              .where((item) => item.id >= 7101 && item.id <= 7107)
              .map((item) => item.id - 7100)
              .toSet();
          if (actual.length != days.length || !actual.containsAll(days)) {
            throw StateError('Lịch chưa được cài trên máy.');
          }
          await preferences.setString('signvoice_alarm_plan', plan);
        }
        scheduledReminderCount = days.length;
        final upcoming =
            days
                .map(
                  (day) =>
                      reminder.nextForDay(day, tz.TZDateTime.now(tz.local)),
                )
                .toList()
              ..sort();
        nextReminder = upcoming.firstOrNull;
      } catch (_) {
        error = 'Chưa cài được lịch nhắc trên điện thoại. Hãy kiểm tra quyền và thử lại.';
      } finally {
        if (generation == _generation && !_disposed) _enqueuePush(generation);
        _notify();
      }
    });
  }

  Future<void> retry({bool waitForPush = false}) async {
    error = null;
    if (supported && state.persisted && !_disposed) {
      try {
        await initialize();
      } catch (_) {
        error = 'Chưa khởi tạo được thông báo trên máy này.';
      }
      _signature = null;
      refresh();
      await _queue;
      if (waitForPush) await _pushQueue;
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

  Future<void> testScheduledReminder() async {
    if (!await requestPermission(exactAlarm: true)) {
      throw StateError('Hãy cho phép thông báo trong Cài đặt ứng dụng.');
    }
    await _local.zonedSchedule(
      id: 7098,
      title: 'Thử lịch nhắc học SignVoice',
      body: 'Lịch nhắc trên điện thoại đã hoạt động.',
      scheduledDate: tz.TZDateTime.now(tz.local)
          .add(const Duration(minutes: 1)),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'signvoice_study',
          'Nhắc học',
          icon: 'ic_stat_study',
          importance: Importance.high,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: '/learn?tab=1',
    );
    if (!(await _local.pendingNotificationRequests()).any(
      (item) => item.id == 7098,
    )) {
      throw StateError('Chưa cài được lịch thử.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _inboxGeneration++;
    _inboxTimer?.cancel();
    _cancelVisibility?.call();
    _generation++;
    state.removeListener(refresh);
    _tokens?.cancel();
    _messages?.cancel();
    _opened?.cancel();
    super.dispose();
  }
}
