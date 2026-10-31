import 'package:flutter/material.dart';

import '../../widgets/ui.dart';

class LearningDailyGoals extends StatelessWidget {
  const LearningDailyGoals({
    super.key,
    required this.today,
    required this.goals,
    required this.onEdit,
    this.lastSynced,
    this.syncError,
    this.onEditLabel = 'Đổi mục tiêu',
  });
  final Map today, goals;
  final String onEditLabel;
  final VoidCallback onEdit;
  final DateTime? lastSynced;
  final String? syncError;
  @override
  Widget build(BuildContext context) {
    int count(Map value, String key) => (value[key] as num? ?? 0).toInt();
    final fresh = count(today, 'newWords'), review = count(today, 'reviewed');
    final freshTarget = count(goals, 'newWords'),
        reviewTarget = count(goals, 'reviewWords');
    final complete =
        fresh >= freshTarget &&
        review >= reviewTarget &&
        freshTarget > 0 &&
        reviewTarget > 0;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 500);
    final date = '${today['date'] ?? ''}';
    String two(int value) => '$value'.padLeft(2, '0');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Heading('Mục tiêu hôm nay', size: 22),
                  BodyText(date.split('-').reversed.join('/')),
                ],
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded),
                label: Text(onEditLabel),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _GoalTile(
            key: const ValueKey('goal-new'),
            day: date,
            done: fresh,
            target: freshTarget,
            label: 'Đã học',
            suffix: 'từ mới',
            completedLabel: 'Hoàn thành mục tiêu học',
            icon: Icons.auto_stories_rounded,
          ),
          const SizedBox(height: 12),
          _GoalTile(
            key: const ValueKey('goal-review'),
            day: date,
            done: review,
            target: reviewTarget,
            label: 'Đã ôn',
            suffix: 'từ',
            completedLabel: 'Hoàn thành mục tiêu ôn',
            icon: Icons.replay_rounded,
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: duration,
            child: complete
                ? Container(
                    key: const ValueKey('goals-complete'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF15803D).withAlpha(22),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Bạn đã hoàn thành cả hai mục tiêu hôm nay!',
                      style: TextStyle(
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                syncError == null
                    ? Icons.sync_rounded
                    : Icons.cloud_off_rounded,
                size: 16,
                color: syncError == null
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFFB45309),
              ),
              Text(
                syncError == null
                    ? 'Đã cập nhật'
                    : 'Đang giữ số liệu lần cập nhật trước',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (lastSynced != null)
                Text(
                  '· ${two(lastSynced!.hour)}:${two(lastSynced!.minute)}:${two(lastSynced!.second)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          if (syncError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Notice(syncError!),
            ),
          const ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Cách tính mục tiêu'),
            children: [
              BodyText(
                'Từ mới là lần đầu ghi nhận tiến độ của từ. Từ ôn là các từ trong quiz camera đã nộp, mỗi từ tính một lần trong ngày. Nhận diện chưa khớp vẫn là một lượt thực hành, không tự coi là đã nhớ.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    super.key,
    required this.day,
    required this.done,
    required this.target,
    required this.label,
    required this.suffix,
    required this.completedLabel,
    required this.icon,
  });
  final String day, label, suffix, completedLabel;
  final int done, target;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final complete = target > 0 && done >= target;
    final color = complete
        ? const Color(0xFF15803D)
        : Theme.of(context).colorScheme.primary;
    final ratio = target > 0 ? (done / target).clamp(0.0, 1.0) : 0.0;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 650);
    return Semantics(
      liveRegion: true,
      label: '$label $done trên $target $suffix',
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withAlpha(14),
          border: Border.all(color: color.withAlpha(60)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AnimatedSwitcher(
                  duration: duration,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    complete ? Icons.check_circle_rounded : icon,
                    key: ValueKey(complete),
                    color: color,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: duration,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .15),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      '$label $done/$target $suffix',
                      key: ValueKey('$day:$done/$target'),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
              duration: duration,
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: ratio),
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  minHeight: 9,
                  value: value,
                  color: color,
                  backgroundColor: color.withAlpha(24),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              complete
                  ? completedLabel
                  : 'Còn ${target - done} từ để hoàn thành',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
