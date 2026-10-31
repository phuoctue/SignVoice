import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../core/navigation.dart';
import '../services/notifications/notification_service.dart';
import 'ui.dart' show AppCard, EmptyView, Notice;
import 'notification_updates_switch.dart';

Future<void> showNotificationInbox(BuildContext context) async {
  final service = context.read<NotificationService>();
  final box = context.findRenderObject() as RenderBox?;
  final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
  final size = MediaQuery.sizeOf(context);
  final top = (origin.dy + (box?.size.height ?? 48) + 8).clamp(
    12.0,
    (size.height - 180).clamp(12.0, double.infinity),
  );
  final width = (size.width - 24).clamp(0.0, 420.0);
  final right = (size.width - origin.dx - (box?.size.width ?? 48)).clamp(
    12.0,
    (size.width - width - 12).clamp(12.0, double.infinity),
  );
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Đóng thông báo',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, animation, secondary) => Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          width: width,
          child: ChangeNotifierProvider.value(
            value: service,
            child: NotificationInboxDialog(
              maxHeight: (size.height - top - 16).clamp(180.0, 600.0),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (_, animation, secondary, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context) {
    final unread = context.watch<NotificationService>().unreadCount;
    return IconButton(
      tooltip: unread == 0 ? 'Thông báo' : 'Thông báo, $unread chưa đọc',
      onPressed: () => showNotificationInbox(context),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}

class NotificationInboxDialog extends StatefulWidget {
  const NotificationInboxDialog({super.key, this.maxHeight = 560});
  final double maxHeight;
  @override
  State<NotificationInboxDialog> createState() =>
      _NotificationInboxDialogState();
}

class _NotificationInboxDialogState extends State<NotificationInboxDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationService>().loadInbox(force: true);
    });
  }

  String timestamp(Map<String, dynamic> item) {
    final date = DateTime.tryParse('${item['createdAt']}');
    return date == null
        ? ''
        : ' · ${DateFormat('dd/MM HH:mm').format(date.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<NotificationService>();
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 420,
        height: (260.0 + inbox.inbox.length * 140).clamp(
          widget.maxHeight < 260 ? widget.maxHeight : 260.0,
          widget.maxHeight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Thông báo',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng thông báo',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (inbox.inboxLoading) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const NotificationUpdatesSwitch(),
                  const SizedBox(height: 12),
                  if (inbox.inboxError != null) Notice(inbox.inboxError!),
                  if (!inbox.inboxLoading &&
                      inbox.inboxError == null &&
                      inbox.inbox.isEmpty)
                    const EmptyView(
                      title: 'Chưa có thông báo',
                      description: 'Lời nhắc đến giờ học và cập nhật mới sẽ xuất hiện ở đây.',
                    ),
                  for (final item in inbox.inbox)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        onTap: () async {
                          if (!await inbox.markRead(item) || !context.mounted) {
                            return;
                          }
                          final route = item['route'];
                          final destination =
                              route == '/learn' || route == '/learn?tab=1'
                              ? route as String
                              : null;
                          Navigator.pop(context);
                          if (destination != null) {
                            openRoot(context, destination);
                          }
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              item['kind'] == 'STUDY_REMINDER'
                                  ? Icons.alarm
                                  : Icons.notifications_outlined,
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
                                  Text('${item['body']}'),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${item['read'] == true ? 'Đã đọc' : 'Chưa đọc'}${timestamp(item)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
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
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: inbox.inboxLoading
                      ? null
                      : () => inbox.loadInbox(force: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tải lại thông báo'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
