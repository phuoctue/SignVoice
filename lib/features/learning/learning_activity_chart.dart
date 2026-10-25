import 'dart:math' as math;

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
    const learnedColor = Color(0xFF2563EB), reviewedColor = Color(0xFF087F6E);
    final labelSize = MediaQuery.textScalerOf(context).scale(10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Wrap(
          spacing: 18,
          children: [
            Text('● Học', style: TextStyle(color: learnedColor)),
            Text('● Ôn', style: TextStyle(color: reviewedColor)),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, size) => SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(
                size.maxWidth,
                widget.days.length * math.max(32.0, labelSize * 2 + 8),
              ),
              height: 132 + labelSize * 1.5,
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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  SizedBox(
                                    height: 112,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Expanded(
                                          child: bar(
                                            count(widget.days[i], 'learned') /
                                                maximum *
                                                104,
                                            learnedColor,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Expanded(
                                          child: bar(
                                            count(widget.days[i], 'reviewed') /
                                                maximum *
                                                104,
                                            reviewedColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${widget.days[i]['date']}'.split('-').last,
                                    style: TextStyle(
                                      fontSize: 10,
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
        const SizedBox(height: 12),
        Text(
          'Ngày ${chosen['date']}: học ${count(chosen, 'learned')} từ · ôn ${count(chosen, 'reviewed')} từ',
        ),
        Text(
          widget.onDaySelected == null
              ? 'Chạm cột để xem từng ngày; vuốt ngang khi cần.'
              : 'Chạm vào một ngày để xem các từ đã học và ôn.',
        ),
      ],
    );
  }
}
