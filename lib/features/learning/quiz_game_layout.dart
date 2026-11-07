import 'package:flutter/material.dart';

import 'quiz_game_style.dart';

class QuizGameScaffold extends StatelessWidget {
  const QuizGameScaffold({
    super.key,
    required this.child,
    required this.onBack,
    required this.onReload,
    required this.solved,
    required this.total,
    required this.firstTry,
    this.dock,
    this.controller,
    this.completed = false,
  });
  final Widget child;
  final VoidCallback? onBack, onReload;
  final int solved, total, firstTry;
  final bool completed;
  final Widget? dock;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) {
    final palette = QuizGamePalette(context);
    return Theme(
      data: palette.theme(Theme.of(context)),
      child: Builder(
        builder: (context) {
          final p = QuizGamePalette(context);
          return Scaffold(
            backgroundColor: p.background,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [p.background, p.backgroundEnd],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _QuizHeader(
                      onBack: onBack,
                      onReload: onReload,
                      solved: solved,
                      total: total,
                      firstTry: firstTry,
                      completed: completed,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: controller,
                        padding: EdgeInsets.all(
                          MediaQuery.sizeOf(context).width >= 900 ? 32 : 16,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1280),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: dock,
          );
        },
      ),
    );
  }
}

class _QuizHeader extends StatelessWidget {
  const _QuizHeader({
    required this.onBack,
    required this.onReload,
    required this.solved,
    required this.total,
    required this.firstTry,
    required this.completed,
  });
  final VoidCallback? onBack, onReload;
  final int solved, total, firstTry;
  final bool completed;
  Widget stat(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool warm = false,
  }) {
    final p = QuizGamePalette(context), color = warm ? p.amber : p.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: warm ? p.amberSurface : p.soft,
        border: Border.all(color: color.withValues(alpha: .2)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = QuizGamePalette(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: .94),
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1344),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: LayoutBuilder(
              builder: (context, size) {
                final compact =
                    size.maxWidth < 860 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.4;
                final short = MediaQuery.sizeOf(context).height < 500;
                final details = Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: p.soft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: IconButton(
                        tooltip: 'Quay lại',
                        onPressed: onBack,
                        icon: Icon(Icons.arrow_back_rounded, color: p.primary),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!short) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: p.soft,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    completed
                                        ? 'ĐÃ HOÀN TẤT'
                                        : 'ÔN TẬP KÝ HIỆU',
                                    style: TextStyle(
                                      color: p.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: .7,
                                    ),
                                  ),
                                ),
                                if (size.maxWidth > 480)
                                  Text(
                                    '• Tự động lưu',
                                    style: TextStyle(
                                      color: p.muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          QuizGradientTitle(
                            'Ghép cặp ký hiệu',
                            size: compact ? 20 : 24,
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      stat(
                        context,
                        icon: Icons.local_fire_department_rounded,
                        label: 'ĐÚNG LẦN ĐẦU',
                        value: '$firstTry cặp',
                        warm: true,
                      ),
                      const SizedBox(width: 16),
                      stat(
                        context,
                        icon: Icons.emoji_events_rounded,
                        label: 'ĐÃ GHÉP',
                        value: '$solved / $total',
                      ),
                      const SizedBox(width: 16),
                    ],
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: p.surface,
                        border: Border.all(color: p.line),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: IconButton(
                        tooltip: 'Tải trạng thái đã lưu',
                        onPressed: onReload,
                        icon: Icon(Icons.refresh_rounded, color: p.muted),
                      ),
                    ),
                  ],
                );
                return details;
              },
            ),
          ),
        ),
      ),
    );
  }
}

class QuizInstructionBanner extends StatelessWidget {
  const QuizInstructionBanner({
    super.key,
    required this.round,
    required this.roundCount,
    required this.solved,
    required this.total,
  });
  final int round, roundCount, solved, total;
  @override
  Widget build(BuildContext context) {
    final p = QuizGamePalette(context),
        progress = total == 0 ? 0.0 : solved / total;
    final progressView = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.soft.withValues(alpha: .65),
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'Tiến độ hoàn thành',
                style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: p.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Đã ghép $solved/$total cặp',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 10,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: p.line)),
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: p.gradient),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Đã ghép $solved/$total cặp · Tự động lưu',
            style: TextStyle(color: p.muted, fontSize: 11),
          ),
        ],
      ),
    );
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: p.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Thử thách Vòng ${round + 1}/$roundCount',
                style: TextStyle(
                  color: p.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Xem mẫu video ký hiệu rồi kéo hoặc chạm thẻ nghĩa đặt vào ô tương ứng bên dưới.',
          style: TextStyle(
            color: p.muted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.6,
          ),
        ),
      ],
    );
    return QuizGlassPanel(
      child: LayoutBuilder(
        builder: (context, size) {
          if (size.maxWidth >= 760 &&
              MediaQuery.textScalerOf(context).scale(1) < 1.5) {
            return Row(
              children: [
                Expanded(child: intro),
                const SizedBox(width: 32),
                SizedBox(width: 280, child: progressView),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [intro, const SizedBox(height: 18), progressView],
          );
        },
      ),
    );
  }
}

class QuizMeaningDock extends StatelessWidget {
  const QuizMeaningDock({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final p = QuizGamePalette(context),
        short = MediaQuery.sizeOf(context).height < 500;
    return Container(
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: .97),
        border: Border(top: BorderSide(color: p.line)),
        boxShadow: [
          BoxShadow(
            color: p.primary.withValues(alpha: .07),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .36,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: short ? 10 : 20,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: LayoutBuilder(
                  builder: (context, size) {
                    final compact =
                        size.maxWidth < 940 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.4;
                    final label = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: p.gradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.sell_outlined,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kho thẻ nghĩa',
                                style: TextStyle(
                                  color: p.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (!short &&
                                  MediaQuery.textScalerOf(context).scale(1) <
                                      1.5)
                                Text(
                                  'Kéo thả hoặc bấm chọn thẻ để ghép vào ô',
                                  style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final tags = Wrap(
                      alignment: compact
                          ? WrapAlignment.center
                          : WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 12,
                      children: children,
                    );
                    if (!compact) {
                      return Row(
                        children: [
                          SizedBox(width: 300, child: label),
                          const SizedBox(width: 24),
                          Expanded(child: tags),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        label,
                        SizedBox(height: short ? 8 : 14),
                        tags,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuizRoundDialog extends StatelessWidget {
  const QuizRoundDialog({
    super.key,
    required this.lastRound,
    required this.onContinue,
  });
  final bool lastRound;
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) {
    final p = QuizGamePalette(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Stack(
          children: [
            QuizGlassPanel(
              padding: const EdgeInsets.all(30),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            p.success,
                            p.dark
                                ? const Color(0xFF5EDCC3)
                                : const Color(0xFF14B8A6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        size: 42,
                        color: p.dark ? const Color(0xFF102D28) : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Tuyệt vời!',
                      style: TextStyle(
                        color: p.ink,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Bạn đã ghép đủ các cặp ký hiệu trong vòng này. Cùng tiếp tục củng cố những từ vừa học nhé!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: QuizGradientButton(
                        lastRound
                            ? 'Hoàn tất và lưu kết quả'
                            : 'Vòng tiếp theo',
                        onPressed: onContinue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Positioned.fill(child: QuizCelebration()),
          ],
        ),
      ),
    );
  }
}

class QuizResultHero extends StatelessWidget {
  const QuizResultHero({
    super.key,
    required this.points,
    required this.firstTry,
    required this.practiced,
  });
  final Object points, firstTry, practiced;
  @override
  Widget build(BuildContext context) {
    final p = QuizGamePalette(context);
    return QuizGlassPanel(
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: p.gradient,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 42,
            ),
          ),
          const SizedBox(height: 20),
          const QuizGradientTitle('Hoàn thành lượt ghép cặp!', size: 28),
          const SizedBox(height: 12),
          Text(
            '$points điểm thưởng',
            style: TextStyle(
              color: p.primary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _resultBadge(
                context,
                '$firstTry',
                'Đúng ngay lần đầu',
                Icons.verified_rounded,
              ),
              _resultBadge(
                context,
                '$practiced',
                'Có luyện lại / gợi ý',
                Icons.lightbulb_outline_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultBadge(
    BuildContext context,
    String value,
    String label,
    IconData icon,
  ) {
    final p = QuizGamePalette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: p.soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: p.primary, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: p.primary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
