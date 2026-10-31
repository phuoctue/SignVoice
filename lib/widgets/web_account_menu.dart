import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/navigation.dart';
import '../providers/auth_provider.dart';
import 'ui.dart' show confirm;
import 'user_avatar.dart';

class WebAccountMenu extends StatelessWidget {
  const WebAccountMenu({super.key, this.sidebar = false, this.expanded = true});
  final bool sidebar, expanded;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final auth = context.watch<AuthProvider>();
    final guest = auth.user?.isGuest == true;
    final name = guest
        ? 'Khách'
        : state.name.isNotEmpty
        ? state.name
        : auth.user?.displayName ?? 'Tài khoản';
    final url = state.ready ? state.avatarUrl : auth.user?.avatarUrl ?? '';
    final scheme = Theme.of(context).colorScheme;
    Widget avatar(double radius) => UserAvatar(
      accountId: state.accountId,
      name: name,
      url: url,
      color: avatarColors[state.avatarColor.clamp(0, avatarColors.length - 1)],
      radius: radius,
    );
    PopupMenuItem<String> item(
      String path,
      String label,
      IconData icon, {
      bool danger = false,
    }) => PopupMenuItem(
      value: path,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: danger ? scheme.error : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: danger ? scheme.error : scheme.onSurface),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: sidebar
          ? const EdgeInsets.symmetric(horizontal: 8)
          : const EdgeInsets.only(left: 8, right: 16),
      child: PopupMenuButton<String>(
        tooltip: sidebar ? 'Tài khoản trên thanh điều hướng' : 'Menu tài khoản',
        position: PopupMenuPosition.under,
        offset: sidebar ? const Offset(0, -8) : const Offset(0, 8),
        constraints: BoxConstraints(
          minWidth: sidebar && expanded ? 232 : 260,
          maxWidth: sidebar && expanded ? 232 : 320,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onSelected: (path) async {
          if (path != 'logout') {
            openScreen(context, path);
            return;
          }
          if (!await confirm(
            context,
            title: 'Đăng xuất?',
            message: 'Bạn có muốn đăng xuất khỏi tài khoản hiện tại?',
            confirmLabel: 'Đăng xuất',
            destructive: true,
          )) {
            return;
          }
          if (!context.mounted) return;
          await auth.logout();
          if (context.mounted) openRoot(context, '/login');
        },
        itemBuilder: (_) => [
          if (!sidebar)
            PopupMenuItem<String>(
              enabled: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    avatar(22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.email.isNotEmpty
                                ? state.email
                                : auth.user?.email ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!sidebar) const PopupMenuDivider(),
          if (!guest) item('/profile', 'Hồ sơ', Icons.person_outline),
          if (!sidebar) ...[
            if (!guest)
              item('/study-reminder', 'Lịch học', Icons.event_note_outlined),
            item('S27', 'Cài đặt giọng nói', Icons.headphones_outlined),
            item(
              'S28',
              'Giao diện & Trợ năng',
              Icons.accessibility_new_outlined,
            ),
          ],
          const PopupMenuDivider(),
          item('logout', 'Đăng xuất', Icons.logout, danger: true),
        ],
        icon: sidebar ? null : avatar(18),
        iconSize: 36,
        padding: const EdgeInsets.all(6),
        child: sidebar
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    avatar(18),
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 18),
                    ],
                  ],
                ),
              )
            : null,
      ),
    );
  }
}
