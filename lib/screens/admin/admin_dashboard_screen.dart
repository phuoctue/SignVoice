import '../../core/navigation.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../../widgets/ui.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AdminRecord? _stats;
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>(),
          epoch = context.read<AuthProvider>().accountEpoch;
      final service = context.read<AdminWorkspaceService>();
      final results = await Future.wait<dynamic>([
        auth.refreshUser(),
        service.stats(),
      ]);
      if (mounted && auth.accountEpoch == epoch && auth.isStaff) {
        setState(() => _stats = results[1] as AdminRecord);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không tải được thống kê. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return AppPage(
      title: 'Quản trị',
      showBack: false,
      tabIndex: 4,
      scroll: false,
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text('Tổng quan', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              auth.isAdmin
                  ? 'Quản lý hệ thống và nội dung'
                  : 'Quản lý từ điển, danh mục và duyệt nội dung',
            ),
            const SizedBox(height: 18),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_stats != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns =
                      MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
                          width < 320
                      ? 1
                      : width >= 700
                      ? 3
                      : 2;
                  final statWidth = (width - 10 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (auth.isAdmin && auth.can('users:read'))
                        _stat(
                          'Tài khoản',
                          _stats!['users']['total'],
                          Icons.people_outline,
                          statWidth,
                        ),
                      if (auth.can('dictionary:read')) ...[
                        _stat(
                          'Mục từ điển',
                          _stats!['content']['total'],
                          Icons.menu_book,
                          statWidth,
                        ),
                        _stat(
                          'Đã xuất bản',
                          _stats!['content']['published'],
                          Icons.check_circle_outline,
                          statWidth,
                        ),
                        _stat(
                          'Bản nháp',
                          _stats!['content']['pending'],
                          Icons.edit_note,
                          statWidth,
                        ),
                      ],
                      if (auth.isAdmin && auth.can('sessions:read'))
                        _stat(
                          'Phiên hoạt động',
                          _stats!['sessions']['active'],
                          Icons.devices,
                          statWidth,
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 24),
            Text('Quản lý', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            for (final module in adminModules.entries)
              if (auth.can('${module.key}:read') &&
                  (auth.isAdmin ||
                      !const [
                        'users',
                        'roles',
                        'sessions',
                      ].contains(module.key)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        module.value.icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(module.value.title),
                      subtitle: Text(module.value.description),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          pushAppRoute(context, '/admin/${module.key}'),
                    ),
                  ),
                ),
            if (auth.can('dictionary:read'))
              AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Duyệt nội dung'),
                  subtitle: const Text('Kiểm tra và xuất bản bản nháp'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => pushAppRoute(context, '/admin/content'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, dynamic value, IconData icon, double width) =>
      SizedBox(
        width: width,
        child: AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text('$value', style: Theme.of(context).textTheme.headlineSmall),
              Text(label),
            ],
          ),
        ),
      );
}

class AdminModule {
  const AdminModule(this.title, this.description, this.icon);
  final String title, description;
  final IconData icon;
}

const adminModules = {
  'users': AdminModule(
    'Tài khoản',
    'Tạo tài khoản, gán role và khóa tài khoản',
    Icons.people_outline,
  ),
  'roles': AdminModule(
    'Role & phân quyền',
    'Tạo role tùy chỉnh và chọn bộ quyền',
    Icons.admin_panel_settings_outlined,
  ),
  'dictionary': AdminModule(
    'Từ điển',
    'Thêm, sửa, xóa và xuất bản mục từ',
    Icons.menu_book_outlined,
  ),
  'categories': AdminModule(
    'Danh mục',
    'Sắp xếp và quản lý chủ đề từ điển',
    Icons.category_outlined,
  ),
  'collections': AdminModule(
    'Bộ sưu tập công khai',
    'Xem nội dung, xử lý báo cáo và kiểm duyệt chia sẻ',
    Icons.collections_bookmark_outlined,
  ),
  'sessions': AdminModule(
    'Phiên đăng nhập',
    'Xem thiết bị và thu hồi phiên',
    Icons.devices_outlined,
  ),
};
