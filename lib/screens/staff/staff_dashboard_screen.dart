import '../../core/navigation.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/staff_provider.dart';
import '../../widgets/ui.dart';

/// Staff dashboard screen
class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StaffProvider>().loadStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final staffProvider = context.watch<StaffProvider>();
    final stats = staffProvider.stats;

    return Scaffold(
      appBar: AppBar(title: const Text('Khu vực nhân viên')),
      bottomNavigationBar: const AppNavigationBar(selectedIndex: 4),
      body: RefreshIndicator(
        onRefresh: () => staffProvider.loadStats(),
        child: staffProvider.isLoading && stats == null
            ? const Center(child: CircularProgressIndicator())
            : staffProvider.errorMessage != null && stats == null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Lỗi: ${staffProvider.errorMessage}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => staffProvider.loadStats(),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Thống kê',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),

                  // Content stats
                  if (stats != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Chờ duyệt',
                            value: stats.content.pending.toString(),
                            icon: Icons.pending_actions,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            title: 'Đã xuất bản',
                            value: stats.content.published.toString(),
                            icon: Icons.check_circle,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // User stats
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Tổng người dùng',
                            value: stats.users.total.toString(),
                            icon: Icons.people,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            title: 'Tuần này',
                            value: stats.users.recentWeek.toString(),
                            icon: Icons.person_add,
                            color: Colors.purple,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Quick actions
                  Text(
                    'Thao tác nhanh',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.rate_review),
                          title: const Text('Xét duyệt nội dung'),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: () => pushAppRoute(
                            context,
                            '/staff/content',
                            arguments: {'filter': 'pending'},
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.library_books),
                          title: const Text('Quản lý nội dung'),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: () => pushAppRoute(context, '/staff/content'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.people_outline),
                          title: const Text('Xem người dùng'),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: () => pushAppRoute(context, '/staff/users'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
