import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api/api_exception.dart';
import '../../providers/auth_provider.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'learning_activity_chart.dart';
import 'learning_widgets.dart';
import 'learning_daily_goals.dart';
import 'learning_day_sheet.dart';

class LearningInsightsScreen extends StatefulWidget {
  const LearningInsightsScreen({super.key});
  @override
  State<LearningInsightsScreen> createState() => _LearningInsightsScreenState();
}

class _LearningInsightsScreenState extends State<LearningInsightsScreen>
    with WidgetsBindingObserver {
  int days = 7, page = 1, request = 0;
  bool loading = true;
  bool refreshing = false;
  DateTime? lastSynced;
  String? syncError;
  String? error;
  LearningRecord? data;
  LearningService get service => context.read<LearningService>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    request++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !refreshing) {
      load(silent: data != null);
    }
  }

  Future<void> load({bool silent = false}) async {
    final current = ++request;
    refreshing = true;
    setState(() {
      if (!silent || data == null) loading = true;
      error = null;
    });
    try {
      final result = await service.insights(days: days, page: page);
      if (!mounted || current != request) return;
      final weak = LearningPage.fromJson(
        LearningRecord.from(result['weakWords'] as Map),
      );
      if (page > weak.pages) {
        page = weak.pages;
        await load(silent: silent);
        return;
      }
      setState(() {
        data = result;
        syncError = null;
        lastSynced = DateTime.now();
      });
    } catch (e) {
      if (mounted && current == request) {
        setState(() {
          final message = e is ApiException
              ? e.message
              : 'Chưa tải được thống kê. Hãy thử lại.';
          if (silent && data != null) {
            syncError = message;
          } else {
            error = message;
          }
        });
      }
    } finally {
      if (mounted && current == request) {
        setState(() {
          loading = false;
          refreshing = false;
        });
      }
    }
  }

  Future<void> showDay(LearningRecord day) async {
    final activeService = service;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LearningDaySheet(
        date: '${day['date']}',
        service: activeService,
        initialKind: (day['learned'] as num? ?? 0) > 0 ? 'learned' : 'reviewed',
      ),
    );
    if (mounted) await load(silent: true);
  }

  Future<void> editGoals(Map goals) async {
    final activeService = service;
    final owner = context.read<AuthProvider>().user?.id;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _GoalDialog(
        goals: goals,
        onSave: (fresh, review) async {
          if (!mounted || context.read<AuthProvider>().user?.id != owner) {
            throw ApiException(
              message: 'Tài khoản đã thay đổi. Hãy mở lại mục tiêu.',
            );
          }
          await activeService.saveGoals(newWords: fresh, reviewWords: review);
        },
      ),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> open(String route) async {
    await Navigator.pushNamed(context, route);
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final result = data;
    final today = result?['today'] as Map? ?? {};
    final goals =
        result?['goals'] as Map? ?? {'newWords': 5, 'reviewWords': 10};
    final activity = (result?['activity'] as List? ?? [])
        .map((row) => LearningRecord.from(row as Map))
        .toList();
    final weak = LearningPage.fromJson(
      LearningRecord.from(result?['weakWords'] as Map? ?? {}),
    );
    return AppPage(
      title: 'Thống kê & mục tiêu',
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BodyText('Hoạt động học tập theo giờ Việt Nam (UTC+7).'),
          const SizedBox(height: 16),
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Notice(error!),
            TextButton(onPressed: load, child: const Text('Thử lại')),
          ],
          if (!loading && error == null && result != null) ...[
            LearningDailyGoals(
              today: today,
              goals: goals,
              onEdit: () => editGoals(goals),
              lastSynced: lastSynced,
              syncError: syncError,
            ),
            const SizedBox(height: 18),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Heading('Hoạt động học và ôn', size: 21),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: days,
                          isExpanded: true,
                          items: [
                            for (final range in [7, 30])
                              DropdownMenuItem(
                                value: range,
                                child: Text('$range ngày'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null && value != days) {
                              days = value;
                              page = 1;
                              load();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  LearningActivityChart(
                    key: ValueKey(days),
                    days: activity,
                    onDaySelected: showDay,
                  ),
                  const SizedBox(height: 12),
                  const BodyText(
                    'Học: số từ tự đánh giá. Ôn: số từ trong quiz camera đã hoàn tất. Mỗi từ chỉ tính một lần mỗi ngày trong từng nhóm; lịch sử cũ chỉ có trạng thái không được coi là một lượt học.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Heading('Từ cần củng cố', size: 22),
            const SizedBox(height: 8),
            const BodyText(
              'Sau khi nộp quiz camera, các từ từng nhận diện chưa khớp sẽ xuất hiện ở đây.',
            ),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Mục củng cố hoạt động thế nào?'),
              children: [
                BodyText(
                  '1. Vào chủ đề đã học, chọn bộ lọc Ôn tập → Bắt đầu quiz ôn tập. Nếu chưa có từ ôn, chọn Ôn tập ở từ đang học cần luyện.\n2. Làm ký hiệu bằng camera, ghi nhận kết quả từng từ rồi nộp quiz.\n3. Các từ chưa khớp được xếp theo số lượt cần luyện trong 30 ngày.\nNếu lần gần nhất đã khớp, từ vẫn có thể còn trong danh sách do các lượt chưa khớp trước đó. Xem lại mẫu hoặc mở chủ đề để luyện tiếp.',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (weak.items.isEmpty)
              const EmptyView(
                title: 'Chưa có từ cần củng cố',
                description: 'Chưa có quiz camera đã nộp hoặc chưa có từ nhận diện chưa khớp trong 30 ngày. Hãy vào Đang học → chủ đề → Ôn tập để bắt đầu.',
                icon: Icons.task_alt,
              ),
            for (final word in weak.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Heading('${word['word']}', size: 19),
                      BodyText('${word['topicName']}'),
                      const SizedBox(height: 8),
                      BodyText(
                        '${word['misses']} / ${word['attempts']} lượt chưa khớp (${word['missRate']}%)',
                      ),
                      BodyText(
                        word['latestMatched'] == true
                            ? 'Lần gần nhất: đã khớp'
                            : 'Lần gần nhất: chưa khớp',
                      ),
                      const SizedBox(height: 8),
                      SignVoiceBadge(
                        word['latestMatched'] == true
                            ? 'Đã khớp gần nhất'
                            : 'Nên luyện thêm',
                        color: word['latestMatched'] == true
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          TextButton(
                            onPressed: () => showLearningWord(context, word),
                            child: const Text('Xem ký hiệu'),
                          ),
                          TextButton(
                            onPressed: () =>
                                open('/learn/topic/${word['topicId']}?study=1'),
                            child: const Text('Mở chủ đề'),
                          ),
                          TextButton(
                            onPressed: () => open(
                              '/learn/history?entryId=${word['entryId']}',
                            ),
                            child: const Text('Lịch sử từ'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (weak.pages > 1)
              LearningPager(
                page: page,
                pages: weak.pages,
                onPage: (value) {
                  page = value;
                  load();
                },
              ),
            if (weak.total > 0)
              Text(
                '${weak.total} từ · 10 từ/trang',
                textAlign: TextAlign.center,
              ),
          ],
        ],
      ),
    );
  }
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.goals, required this.onSave});
  final Map goals;
  final Future<void> Function(int newWords, int reviewWords) onSave;
  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  final form = GlobalKey<FormState>();
  late final fresh = TextEditingController(
    text: '${widget.goals['newWords'] ?? 5}',
  );
  late final review = TextEditingController(
    text: '${widget.goals['reviewWords'] ?? 10}',
  );
  bool saving = false;
  String? error;
  @override
  void dispose() {
    fresh.dispose();
    review.dispose();
    super.dispose();
  }

  String? validate(String? value, int max) {
    final count = int.tryParse(value ?? '');
    return count == null || count < 1 || count > max
        ? 'Nhập số nguyên từ 1 đến $max.'
        : null;
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(int.parse(fresh.text), int.parse(review.text));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa lưu được mục tiêu. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Mục tiêu mỗi ngày'),
      content: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: fresh,
                enabled: !saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Từ mới/ngày'),
                validator: (v) => validate(v, 100),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: review,
                enabled: !saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Từ ôn/ngày'),
                validator: (v) => validate(v, 200),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Notice(error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Đang lưu...' : 'Lưu'),
        ),
      ],
    ),
  );
}
