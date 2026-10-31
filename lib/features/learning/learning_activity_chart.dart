import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:intl/intl.dart';

import 'package:flutter/material.dart';

import '../../services/learning/learning_service.dart';

class LearningActivityChart extends StatefulWidget {
  const LearningActivityChart({
    super.key,
    required this.days,
    this.onDaySelected,
  });
  final List<LearningRecord> days;
  final ValueChanged<LearningRecord>? onDaySelected;
  @override
  State<LearningActivityChart> createState() => _LearningActivityChartState();
}

class _LearningActivityChartState extends State<LearningActivityChart> {
  final scroll = ScrollController();
  int? selected;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  int count(LearningRecord row, String key) => (row[key] as num? ?? 0).toInt();
  String dateLabel(Object? value, {bool short = false}) {
    final date = DateTime.tryParse('$value');
    return date == null
        ? 'Chưa có ngày'
        : DateFormat(short ? 'dd/MM' : 'dd/MM/yyyy').format(date);
  }

  Widget bar(double height, Color color) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: height),
    curve: Curves.easeOutCubic,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 500),
    builder: (_, value, _) => Container(
      height: value,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) return const Text('Chưa có hoạt động trong kỳ.');
    final chosen =
        widget.days[(selected ?? widget.days.length - 1).clamp(
          0,
          widget.days.length - 1,
        )];
    final maximum = widget.days.fold<int>(
      1,
      (value, row) => math.max(
        value,
        math.max(count(row, 'learned'), count(row, 'reviewed')),
      ),
    );
    final learnedColor = Theme.of(context).colorScheme.primary;
    final reviewedColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF5EEAD4)
        : const Color(0xFF087F6E);
    final labelSize = MediaQuery.textScalerOf(context).scale(12);
    final valueSize = MediaQuery.textScalerOf(context).scale(11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 18,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: learnedColor),
                const SizedBox(width: 6),
                Text('Học', style: TextStyle(color: learnedColor)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: reviewedColor),
                const SizedBox(width: 6),
                Text('Ôn', style: TextStyle(color: reviewedColor)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, size) => Scrollbar(
            controller: scroll,
            thumbVisibility:
                widget.days.length * math.max(48.0, labelSize * 4 + 12) >
                size.maxWidth,
            interactive: true,
            child: SingleChildScrollView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(
                  size.maxWidth,
                  widget.days.length * math.max(48.0, labelSize * 4 + 12),
                ),
                height: 148 + labelSize * 1.5 + valueSize * 1.5,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < widget.days.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: (selected ?? widget.days.length - 1) == i,
                          label:
                              '${widget.days[i]['date']}: học ${count(widget.days[i], 'learned')} từ, ôn ${count(widget.days[i], 'reviewed')} từ',
                          child: Tooltip(
                            message:
                                '${widget.days[i]['date']}: học ${count(widget.days[i], 'learned')}, ôn ${count(widget.days[i], 'reviewed')}',
                            child: InkWell(
                              onTap: () {
                                setState(() => selected = i);
                                widget.onDaySelected?.call(widget.days[i]);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                      (selected ?? widget.days.length - 1) == i
                                      ? Theme.of(context).colorScheme.primary
                                            .withAlpha(24)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        for (final key in [
                                          'learned',
                                          'reviewed',
                                        ])
                                          Expanded(
                                            child: Text(
                                              widget.days[i][key] is num
                                                  ? '${count(widget.days[i], key)}'
                                                  : '—',
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: key == 'learned'
                                                    ? learnedColor
                                                    : reviewedColor,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 112,
                                      child: Stack(
                                        children: [
                                          const Positioned.fill(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Divider(height: 1),
                                                Divider(height: 1),
                                                Divider(height: 1),
                                              ],
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Expanded(
                                                  child: bar(
                                                    count(
                                                          widget.days[i],
                                                          'learned',
                                                        ) /
                                                        maximum *
                                                        104,
                                                    learnedColor,
                                                  ),
                                                ),
                                                const SizedBox(width: 2),
                                                Expanded(
                                                  child: bar(
                                                    count(
                                                          widget.days[i],
                                                          'reviewed',
                                                        ) /
                                                        maximum *
                                                        104,
                                                    reviewedColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      dateLabel(
                                        widget.days[i]['date'],
                                        short: true,
                                      ),
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight:
                                            (selected ??
                                                    widget.days.length - 1) ==
                                                i
                                            ? FontWeight.w700
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Ngày ${dateLabel(chosen['date'])}: học ${count(chosen, 'learned')} từ · ôn ${count(chosen, 'reviewed')} từ',
        ),
        Text(
          widget.onDaySelected == null
              ? (kIsWeb
                    ? 'Rê chuột hoặc nhấp cột để xem từng ngày.'
                    : 'Chạm cột để xem từng ngày; vuốt ngang khi cần.')
              : (kIsWeb
                    ? 'Nhấp một ngày để xem các từ đã học và ôn.'
                    : 'Chạm vào một ngày để xem các từ đã học và ôn.'),
        ),
      ],
    );
  }
}
