import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notifications/notification_service.dart';
import 'ui.dart' show toast;

class NotificationUpdatesSwitch extends StatefulWidget {
  const NotificationUpdatesSwitch({super.key});
  @override
  State<NotificationUpdatesSwitch> createState() =>
      _NotificationUpdatesSwitchState();
}

class _NotificationUpdatesSwitchState extends State<NotificationUpdatesSwitch> {
  bool saving = false;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<NotificationService>().state;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Nhận cập nhật'),
      subtitle: const Text(
        'Ký hiệu mới và gợi ý ôn tập. Lịch học được đặt riêng.',
      ),
      value: state.notificationsEnabled,
      onChanged: saving
          ? null
          : (value) async {
              final epoch = state.accountEpoch;
              setState(() => saving = true);
              final saved = await state.saveSettings({
                'notificationsEnabled': value,
              });
              if (!mounted || !context.mounted) return;
              setState(() => saving = false);
              if (!saved && state.isCurrent(epoch)) {
                toast(context, 'Chưa lưu được cài đặt thông báo. Hãy thử lại.');
              }
            },
    );
  }
}
