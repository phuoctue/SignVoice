import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../services/notifications/notification_service.dart';
import '../../services/notifications/study_reminder.dart';
import '../../widgets/ui.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool testingPush = false;
  int? inboxRevision;
  int loadGeneration = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    if (!mounted) return;
    final generation = ++loadGeneration;
    final state = AppScope.of(context),
        epoch = AppScope.of(context).accountEpoch;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await state.service?.notifications();
      if (mounted &&
          generation == loadGeneration &&
          (!state.persisted || state.isCurrent(epoch))) {
        setState(
          () => items = (result?['items'] as List? ?? [])
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
        );
      }
    } catch (_) {
      if (mounted && generation == loadGeneration) {
        setState(() => error = 'Chưa tải được thông báo. Hãy thử lại.');
      }
    } finally {
      if (mounted && generation == loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> open(Map<String, dynamic> item) async {
    final state = AppScope.of(context),
        epoch = AppScope.of(context).accountEpoch;
    try {
      await state.service?.readNotification('${item['_id']}');
      if (!mounted || (state.persisted && !state.isCurrent(epoch))) return;
      setState(() => item['read'] = true);
      final route = item['route'];
      if (route == '/learn' || route == '/learn?tab=1') {
        await Navigator.pushNamed(context, route as String);
      }
    } catch (_) {
      if (mounted) toast(context, 'Chưa mở được thông báo. Hãy thử lại.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final device = context.watch<NotificationService>();
    if (inboxRevision != null && inboxRevision != device.inboxRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
    inboxRevision = device.inboxRevision;
    return AppPage(
      title: 'Thông báo',
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Heading('Lịch học của bạn', size: 18),
                const SizedBox(height: 8),
                BodyText(
                  state.studyReminder.enabled && state.notificationsEnabled
                      ? 'Nhắc học lúc ${state.studyReminder.hour.toString().padLeft(2, '0')}:${state.studyReminder.minute.toString().padLeft(2, '0')}'
                      : 'Chọn giờ học để duy trì thói quen mỗi ngày.',
                ),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/study-reminder'),
                  icon: const Icon(Icons.schedule),
                  label: const Text('Đặt lịch & thông báo'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (!device.supported)
            const Notice(
              'Thông báo trên màn hình điện thoại dùng trong ứng dụng Android. Bạn vẫn có thể xem thông báo tại đây.',
            ),
          if (device.supported && !device.permissionGranted)
            AppButton(
              'Cho phép thông báo',
              icon: Icons.notifications_active_outlined,
              onPressed: () async {
                try {
                  final allowed = await device.requestPermission();
                  await device.retry();
                  if (context.mounted && !allowed) {
                    toast(
                      context,
                      'Hãy bật quyền thông báo trong Cài đặt ứng dụng.',
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    toast(context, 'Chưa bật được thông báo. Hãy thử lại.');
                  }
                }
              },
            ),
          if (device.error != null) Notice(device.error!),
          if (device.supported && device.permissionGranted)
            TextButton.icon(
              icon: const Icon(Icons.send_outlined),
              label: Text(testingPush ? 'Đang gửi...' : 'Thử thông báo đẩy'),
              onPressed: testingPush
                  ? null
                  : () async {
                      setState(() => testingPush = true);
                      try {
                        await device.retry();
                        final result = await state.service?.testPush();
                        if (context.mounted) {
                          toast(
                            context,
                            result?['sent'] == true
                                ? 'Firebase đã nhận yêu cầu gửi. Kiểm tra thông báo trên máy.'
                                : 'Đã lưu thông báo; máy chủ đang chờ gửi lại.',
                          );
                        }
                        await load();
                      } catch (_) {
                        if (context.mounted) {
                          toast(
                            context,
                            'Chưa gửi được push. Hãy kiểm tra mạng và đăng ký thiết bị.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => testingPush = false);
                      }
                    },
            ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Notice(error!),
            AppButton('Thử lại', outlined: true, onPressed: load),
          ] else if (!loading && items.isEmpty)
            const EmptyView(
              title: 'Chưa có thông báo',
              description: 'Từ mới và lời nhắc ôn tập sẽ xuất hiện tại đây.',
            ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => open(item),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item['kind'] == 'REVIEW'
                          ? Icons.school_outlined
                          : Icons.menu_book_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['title']}',
                            style: TextStyle(
                              fontWeight: item['read'] == true
                                  ? FontWeight.w500
                                  : FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          BodyText('${item['body']}'),
                          const SizedBox(height: 6),
                          Text(
                            item['read'] == true ? 'Đã đọc' : 'Chưa đọc',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StudyReminderScreen extends StatefulWidget {
  const StudyReminderScreen({super.key});
  @override
  State<StudyReminderScreen> createState() => _StudyReminderScreenState();
}

class _StudyReminderScreenState extends State<StudyReminderScreen> {
  bool? notifications;
  bool enabled = false, saving = false, testing = false;
  late TimeOfDay time;
  final days = <int>{};
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (notifications != null) return;
    final state = AppScope.of(context),
        reminder = AppScope.of(context).studyReminder;
    notifications = state.notificationsEnabled;
    enabled = reminder.enabled;
    time = TimeOfDay(hour: reminder.hour, minute: reminder.minute);
    days.addAll(reminder.weekdays);
  }

  Future<void> save() async {
    if (saving) return;
    if (enabled && days.isEmpty) {
      setState(() => error = 'Chọn ít nhất một ngày học.');
      return;
    }
    final state = AppScope.of(context),
        epoch = AppScope.of(context).accountEpoch;
    final device = context.read<NotificationService>();
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (notifications! &&
          device.supported &&
          !await device.requestPermission(exactAlarm: enabled)) {
        throw StateError(
          'Chưa có quyền thông báo. Hãy bật trong Cài đặt ứng dụng rồi thử lại.',
        );
      }
      if (state.persisted && !state.isCurrent(epoch)) return;
      final success = await state.saveSettings({
        'notificationsEnabled': notifications,
        'studyReminder': StudyReminder(
          enabled: enabled,
          hour: time.hour,
          minute: time.minute,
          weekdays: (days.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : days.toList()
            ..sort()),
          timezone: device.timezone,
        ).toJson(),
      });
      if (!mounted || (state.persisted && !state.isCurrent(epoch))) return;
      if (!success) throw StateError(state.error ?? 'Chưa lưu được lịch học.');
      await device.retry();
      if (mounted) {
        toast(
          context,
          device.error ??
              (device.supported && notifications! && enabled && !device.exact
                  ? 'Đã lưu. Hệ thống có thể nhắc trễ vì chưa cho phép báo thức chính xác.'
                  : 'Đã lưu lịch và cài đặt thông báo.'),
        );
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is StateError
              ? failure.message
              : 'Chưa lưu được. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = context.watch<NotificationService>();
    return PopScope(
      canPop: !saving,
      child: AppPage(
        title: 'Lịch học & thông báo',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nhận thông báo'),
              value: notifications!,
              onChanged: saving
                  ? null
                  : (value) => setState(() => notifications = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nhắc học theo lịch'),
              subtitle: const Text(
                'Nhắc trên điện thoại cả khi ứng dụng đã đóng.',
              ),
              value: enabled,
              onChanged: saving || !notifications!
                  ? null
                  : (value) => setState(() => enabled = value),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time),
                    title: const Text('Giờ học'),
                    trailing: Text(time.format(context)),
                    enabled: !saving && enabled && notifications!,
                    onTap: () async {
                      final result = await showTimePicker(
                        context: context,
                        initialTime: time,
                      );
                      if (mounted && result != null) {
                        setState(() => time = result);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(day == 7 ? 'CN' : 'T${day + 1}'),
                          selected: days.contains(day),
                          onSelected: saving || !enabled || !notifications!
                              ? null
                              : (value) => setState(() {
                                  value ? days.add(day) : days.remove(day);
                                }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            BodyText(
              device.supported
                  ? 'Nhắc học theo giờ trên thiết bị. Từ mới và ôn tập được gửi qua Internet.'
                  : 'Lịch được lưu vào tài khoản. Mở ứng dụng Android để nhận nhắc học trên điện thoại.',
            ),
            if (device.supported && enabled && !device.exact)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Notice(
                  'Khi lưu, cho phép “Báo thức và lời nhắc” để nhắc đúng giờ. Nếu không cấp, hệ thống có thể nhắc trễ.',
                ),
              ),
            if (error != null) Notice(error!),
            const SizedBox(height: 20),
            AppButton(
              'Lưu cài đặt',
              busy: saving,
              onPressed: saving ? null : save,
            ),
            if (device.supported)
              TextButton.icon(
                icon: const Icon(Icons.notifications_outlined),
                label: Text(testing ? 'Đang gửi...' : 'Thử thông báo trên máy'),
                onPressed: saving || testing
                    ? null
                    : () async {
                        setState(() => testing = true);
                        try {
                          await device.testReminder();
                        } catch (_) {
                          if (context.mounted) {
                            toast(
                              context,
                              'Chưa gửi được. Kiểm tra quyền thông báo của ứng dụng.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => testing = false);
                        }
                      },
              ),
          ],
        ),
      ),
    );
  }
}
