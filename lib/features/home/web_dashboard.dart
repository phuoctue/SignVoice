import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import '../learning/learning_daily_goals.dart';
import '../learning/learning_activity_chart.dart';
import '../../services/platform/page_visibility.dart';
import 'featured_dictionary.dart';

/// Web overview reads bounded, account-scoped API responses, never the catalog.
class WebDashboard extends StatefulWidget {
  const WebDashboard({super.key});
  @override
  State<WebDashboard> createState() => _WebDashboardState();
}

class _WebDashboardState extends State<WebDashboard>
    with WidgetsBindingObserver {
  LearningRecord? insights;
  LearningPage? progress;
  bool loading = false;
  String? error;
  int request = 0;
  DateTime? loadedAt;
  late final void Function() cancelVisibility;
  String get continueRoute {
    for (final row in progress?.items ?? <LearningRecord>[]) {
      final summary = row['summary'] as Map? ?? {};
      final topic = row['topic'] as Map? ?? row;
      final id = topic['_id'];
      if (id != null &&
          ((summary['learning'] as num? ?? 0) > 0 ||
              (summary['review'] as num? ?? 0) > 0)) {
        return '/learn/topic/$id?study=1';
      }
    }
    return '/learn';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cancelVisibility = onPageVisible(() {
      if (mounted) load();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancelVisibility();
    request++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !loading) load();
  }

  Future<void> load({bool force = false}) async {
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt!) < const Duration(seconds: 30)) {
      return;
    }
    final auth = context.read<AuthProvider>();
    if (auth.user?.isGuest != false || loading) return;
    final account = auth.accountEpoch, current = ++request;
    final service = context.read<LearningService>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final values = await Future.wait<Object>([
        service.insights(),
        service.progress(),
      ]);
      if (!mounted || current != request || auth.accountEpoch != account) {
        return;
      }
      setState(() {
        loadedAt = DateTime.now();
        insights = values[0] as LearningRecord;
        progress = values[1] as LearningPage;
      });
    } catch (_) {
      if (mounted && current == request && auth.accountEpoch == account) {
        setState(() => error = 'Chưa cập nhật được tiến độ. Hãy thử lại.');
      }
    } finally {
      if (mounted && current == request && auth.accountEpoch == account) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final guest = context.watch<AuthProvider>().user?.isGuest != false;
    final today = insights?['today'] as Map? ?? {};
    final goals = insights?['goals'] as Map? ?? {};
    final summary = progress?.summary ?? {};
    final available = insights != null && progress != null;
    return AppPage(
      preferDesktop: true,
      title: 'Tổng quan',
      showBack: false,
      tabIndex: 0,
      actions: [
        IconButton(
          tooltip: 'Cập nhật tổng quan',
          onPressed: loading || guest ? null : () => load(force: true),
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 16),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 24,
            runSpacing: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BodyText(DateFormat('dd/MM/yyyy').format(DateTime.now())),
                  const SizedBox(height: 8),
                  Heading(
                    'Xin chào, ${state.guest ? 'bạn' : state.name}',
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  const BodyText('Mỗi ký hiệu mới là một cách để kết nối.'),
                ],
              ),
              FilledButton.icon(
                onPressed: () => openScreen(context, continueRoute),
                icon: const Icon(Icons.school_outlined),
                label: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    continueRoute == '/learn'
                        ? 'Khám phá bài học'
                        : 'Tiếp tục học',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (!guest) ...[
            SizedBox(
              height: 4,
              child: loading ? const LinearProgressIndicator() : null,
            ),
            if (error != null)
              Row(
                children: [
                  Expanded(child: Notice(error!)),
                  TextButton(
                    onPressed: loading ? null : () => load(force: true),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
          ],
          if (!guest && loading && !available) const _DashboardSkeleton(),
          if (guest)
            const Notice(
              'Đăng ký tài khoản để lưu và theo dõi tiến độ trên các thiết bị.',
            ),
          if (available)
            LayoutBuilder(
              builder: (context, constraints) {
                final goalsCard = LearningDailyGoals(
                  today: today,
                  goals: goals,
                  syncError: error,
                  lastSynced: loadedAt,
                  onEditLabel: 'Xem & đổi mục tiêu',
                  onEdit: () => openScreen(context, '/learn/insights'),
                );
                final activityCard = _Activity(
                  days: insights?['activity'] as List? ?? [],
                );
                return constraints.maxWidth >= 900 &&
                        MediaQuery.textScalerOf(context).scale(1) < 1.6
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: goalsCard),
                          const SizedBox(width: 24),
                          Expanded(child: activityCard),
                        ],
                      )
                    : Column(
                        children: [
                          goalsCard,
                          const SizedBox(height: 16),
                          activityCard,
                        ],
                      );
              },
            ),
          const SizedBox(height: 32),
          if (!guest) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 540 &&
                        MediaQuery.textScalerOf(context).scale(1) < 1.6
                    ? 2
                    : 1;
                final metrics = <(String, String, IconData)>[
                  (
                    'Tổng đã nhớ',
                    '${summary['remembered'] ?? 0}',
                    Icons.task_alt,
                  ),
                  (
                    'Cần ôn',
                    '${summary['review'] ?? 0}',
                    Icons.event_repeat_outlined,
                  ),
                ];
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 16) /
                            columns,
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(metric.$3, color: scheme.primary),
                              const SizedBox(height: 16),
                              if (!available && loading)
                                Semantics(
                                  label: 'Đang tải ${metric.$1}',
                                  child: Container(
                                    width: 72,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  available ? metric.$2 : 'Chưa có dữ liệu',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              const SizedBox(height: 8),
                              Text(metric.$1),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
          ],
          AdaptiveCardGrid(
            preferDesktop: true,
            children: [
              _Shortcut(
                title: 'Ký hiệu thành giọng nói',
                description:
                    'Mở camera để nhận diện và chuyển ký hiệu thành lời nói.',
                icon: Icons.back_hand_outlined,
                route: '/sign-to-speech',
              ),
              _Shortcut(
                title: 'Giọng nói thành ký hiệu',
                description: 'Nói hoặc nhập nội dung để xem video ký hiệu.',
                icon: Icons.mic_none,
                route: '/speech-to-sign',
              ),
              _Shortcut(
                title: 'Bộ sưu tập của bạn',
                description:
                    'Gom ký hiệu theo tình huống và ôn tập theo cách của bạn.',
                icon: Icons.collections_bookmark_outlined,
                route: '/learn?tab=2',
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              const Expanded(child: Heading('Khám phá từ điển', size: 22)),
              TextButton(
                onPressed: () => openRoot(context, 'S22'),
                child: const Text('Mở từ điển'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const FeaturedDictionary(),
          const SizedBox(height: 32),
          Row(
            children: [
              const Expanded(child: Heading('Hội thoại gần đây', size: 22)),
              TextButton(
                onPressed: () => openRoot(context, 'S20'),
                child: const Text('Xem lịch sử hội thoại'),
              ),
            ],
          ),
          if (state.history.isEmpty)
            const AppCard(
              child: Text('Các hội thoại bạn lưu sẽ xuất hiện tại đây.'),
            ),
          if (state.history.isNotEmpty) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final recent = state.history.take(3).toList();
                final columns = constraints.maxWidth >= 900 ? recent.length : 1;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final item in recent)
                      SizedBox(
                        width:
                            (constraints.maxWidth - (columns - 1) * 16) /
                            columns,
                        child: AppCard(
                          onTap: () {
                            state.selectConversation(item);
                            openScreen(context, '/conversations/${item.id}');
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(switch (item.direction) {
                                    ConversationDirection.signToSpeech =>
                                      Icons.back_hand_outlined,
                                    ConversationDirection.speechToText =>
                                      Icons.mic_none,
                                    _ => Icons.text_fields,
                                  }, color: scheme.primary),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward, size: 18),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height:
                                    MediaQuery.textScalerOf(context).scale(20) *
                                    2.6,
                                child: Text(
                                  item.content.isEmpty
                                      ? 'Hội thoại chưa có nội dung'
                                      : item.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                item.time,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
    );
    Widget card() => AppCard(
      child: SizedBox(
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(180, 24),
            const SizedBox(height: 28),
            block(double.infinity, 80),
            const SizedBox(height: 16),
            block(double.infinity, 80),
            const Spacer(),
            block(160, 14),
          ],
        ),
      ),
    );
    return Semantics(
      label: 'Đang tải mục tiêu và hoạt động',
      child: LayoutBuilder(
        builder: (context, size) {
          final cards = [card(), card()];
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: size.maxWidth >= 900
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 24),
                      Expanded(child: cards[1]),
                    ],
                  )
                : Column(
                    children: [cards[0], const SizedBox(height: 16), cards[1]],
                  ),
          );
        },
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
  });
  final String title, description, route;
  final IconData icon;
  @override
  Widget build(BuildContext context) => AppCard(
    onTap: () => openScreen(context, route),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 170),
      child: IntrinsicHeight(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
            const SizedBox(height: 16),
            Heading(title, size: 19),
            const SizedBox(height: 8),
            BodyText(description),
            const SizedBox(height: 16),
            const Spacer(),
            const Row(
              children: [
                Text('Mở công cụ'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Activity extends StatelessWidget {
  const _Activity({required this.days});
  final List days;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading('Hoạt động 7 ngày', size: 22),
        const SizedBox(height: 8),
        const BodyText('Số từ mới và từ đã ôn mỗi ngày'),
        const SizedBox(height: 16),
        LearningActivityChart(
          days: days
              .whereType<Map>()
              .take(7)
              .map((row) => LearningRecord.from(row))
              .toList(),
        ),
        TextButton(
          onPressed: () => openScreen(context, '/learn/insights'),
          child: const Text('Xem tiến độ chi tiết'),
        ),
      ],
    ),
  );
}
