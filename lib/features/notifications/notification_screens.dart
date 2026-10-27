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
                if (device.supported &&
                    state.studyReminder.enabled &&
                    state.notificationsEnabled)
                  ReminderDeviceStatus(device: device),
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
          if (device.pushError != null) Notice(device.pushError!),
          if (device.supported && device.permissionGranted)
            TextButton.icon(
              icon: const Icon(Icons.send_outlined),
              label: Text(testingPush ? 'Đang gửi...' : 'Thử thông báo đẩy'),
              onPressed: testingPush
                  ? null
                  : () async {
                      setState(() => testingPush = true);
                      try {
                        await device.retry(waitForPush: true);
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
  bool enabled = false, saving = false;
  late TimeOfDay time;
  final days = <int>{};
  String? error;
  bool get hasChanges {
    final state = AppScope.of(context),
        saved = AppScope.of(context).studyReminder;
    return notifications != state.notificationsEnabled ||
        enabled != saved.enabled ||
        time.hour != saved.hour ||
        time.minute != saved.minute ||
        days.length != saved.weekdays.length ||
        !days.containsAll(saved.weekdays);
  }

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
        footer: AppButton(
          'Lưu cài đặt',
          icon: Icons.check,
          busy: saving,
          onPressed: saving ? null : save,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Heading('Lịch nhắc học', size: 22),
            const SizedBox(height: 6),
            const BodyText('Chọn giờ và ngày bạn muốn được nhắc.'),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nhận thông báo'),
              subtitle: const Text('Cho phép ứng dụng gửi lời nhắc cho bạn.'),
              value: notifications!,
              onChanged: saving
                  ? null
                  : (value) => setState(() => notifications = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nhắc học theo lịch'),
              subtitle: const Text(
                'Lặp lại vào những ngày được chọn bên dưới.',
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
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    subtitle: Text(
                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                  const Text(
                    'Lặp lại vào',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
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
            if (error != null) Notice(error!),
            if (hasChanges)
              const Notice(
                'Bạn có thay đổi chưa lưu. Bấm “Lưu cài đặt” để áp dụng lịch mới.',
              ),
            if (device.supported && enabled && notifications!)
              ReminderDeviceStatus(
                device: device,
                controls: true,
                showSchedule: !hasChanges,
                enabled: !saving,
              ),
            if (!device.supported)
              const BodyText(
                'Lịch được lưu vào tài khoản. Mở ứng dụng Android để nhận lời nhắc trên điện thoại.',
              ),
            if (!notifications!)
              const Notice(
                'Thông báo đang tắt. Bật “Nhận thông báo” rồi lưu để nhận lời nhắc.',
              ),
          ],
        ),
      ),
    );
  }
}

class ReminderDeviceStatus extends StatefulWidget {
  const ReminderDeviceStatus({
    super.key,
    required this.device,
    this.controls = false,
    this.showSchedule = true,
    this.enabled = true,
  });
  final NotificationService device;
  final bool controls;
  final bool showSchedule, enabled;
  @override
  State<ReminderDeviceStatus> createState() => _ReminderDeviceStatusState();
}

class _ReminderDeviceStatusState extends State<ReminderDeviceStatus> {
  bool busy = false;
  Future<void> run(Future<void> Function() action, String success) async {
    if (busy || !widget.enabled) return;
    setState(() => busy = true);
    try {
      await action();
      if (mounted) toast(context, widget.device.error ?? success);
    } catch (_) {
      if (mounted) {
        toast(
          context,
          'Chưa thực hiện được. Hãy kiểm tra quyền thông báo và thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device, controls = widget.controls;
    final next = device.nextReminder;
    final now = DateTime.now(), reminder = device.state.studyReminder;
    final passedToday =
        reminder.weekdays.contains(now.weekday) &&
        (now.hour * 60 + now.minute >= reminder.hour * 60 + reminder.minute) &&
        next != null &&
        !DateUtils.isSameDay(next, now);
    const weekdays = [
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ nhật',
    ];
    final allowed = widget.enabled && !busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        if (!device.permissionGranted)
          const Notice('Chưa cho phép thông báo trên điện thoại.'),
        if (device.reminderChannelBlocked)
          const Notice(
            'Mục “Nhắc học” đang bị tắt trong cài đặt thông báo của điện thoại.',
          ),
        if (device.permissionGranted && !device.exact)
          const Notice(
            'Chưa cho phép nhắc đúng giờ. Android có thể trì hoãn lịch đã đặt.',
          ),
        if (device.error != null) Notice(device.error!),
        if (widget.showSchedule &&
            device.scheduledReminderCount > 0 &&
            next != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.event_available_outlined, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lần nhắc tiếp theo',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${weekdays[next.weekday - 1]}, ${next.day.toString().padLeft(2, '0')}/${next.month.toString().padLeft(2, '0')}',
                ),
                if (passedToday)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Giờ nhắc hôm nay đã qua. Ứng dụng sẽ nhắc vào ngày kế tiếp trong lịch.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        if (controls) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: allowed
                ? () => run(
                    device.testScheduledReminder,
                    device.exact
                        ? 'Đã hẹn nhắc thử sau 1 phút. Bạn có thể tắt màn hình để kiểm tra.'
                        : 'Đã hẹn thử. Android có thể nhắc trễ vì chưa cho phép nhắc đúng giờ.',
                  )
                : null,
            icon: const Icon(Icons.timer_outlined),
            label: Text(busy ? 'Đang kiểm tra…' : 'Thử nhắc sau 1 phút'),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            key: const ValueKey('reminder-support'),
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Quyền & hỗ trợ'),
            subtitle: const Text('Mở khi chưa nhận được lời nhắc'),
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Thông báo trên điện thoại'),
                subtitle: Text(
                  device.permissionGranted && !device.reminderChannelBlocked
                      ? 'Đã cho phép'
                      : 'Cần bật quyền thông báo',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: allowed
                    ? () => run(
                        () => device.openDeviceSettings(),
                        'Quay lại ứng dụng sau khi kiểm tra cài đặt.',
                      )
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.alarm_outlined),
                title: const Text('Nhắc đúng giờ'),
                subtitle: Text(
                  device.exact
                      ? 'Đã cho phép'
                      : 'Chưa cho phép · có thể nhắc trễ',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: allowed
                    ? () => run(() async {
                        await device.requestPermission(exactAlarm: true);
                        await device.retry();
                      }, 'Đã kiểm tra quyền nhắc đúng giờ.')
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.battery_saver_outlined),
                title: const Text('Pin và hoạt động nền'),
                subtitle: const Text('Kiểm tra nếu mất nhắc khi tắt màn hình'),
                trailing: const Icon(Icons.chevron_right),
                onTap: allowed
                    ? () => run(
                        () => device.openDeviceSettings(battery: true),
                        'Cho phép SignVoice hoạt động nền trong cài đặt pin.',
                      )
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Kiểm tra lại lịch trên máy'),
                onTap: allowed
                    ? () => run(
                        device.retry,
                        'Đã kiểm tra lại lịch trên điện thoại.',
                      )
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: const Text('Thử thông báo ngay'),
                subtitle: const Text(
                  'Kiểm tra điện thoại có hiển thị thông báo',
                ),
                onTap: allowed
                    ? () => run(
                        device.testReminder,
                        'Đã gửi thông báo thử trên điện thoại.',
                      )
                    : null,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
