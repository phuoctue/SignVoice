import '../../core/navigation.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../services/media/sign_video_source.dart';
import '../../widgets/ui.dart';
import 'learning_page_controller.dart';
import 'learning_widgets.dart';
import 'quiz_mode_sheet.dart';

class TopicLearningScreen extends StatefulWidget {
  const TopicLearningScreen({
    super.key,
    required this.topicId,
    this.study = false,
  });
  final String topicId;
  final bool study;
  @override
  State<TopicLearningScreen> createState() => _TopicLearningScreenState();
}

class _TopicLearningScreenState extends State<TopicLearningScreen> {
  late final LearningPageController controller;
  LearningPage? get data => controller.data;
  int get page => controller.page;
  bool get loading => controller.loading;
  String? get error => controller.error;
  bool saving = false;
  String? ratingId, ratingStage;
  Timer? _warmup;
  String? _prefetched;
  late String stage = widget.study ? 'LEARNING' : 'ALL';
  LearningService get service => context.read<LearningService>();
  @override
  void initState() {
    super.initState();
    final source = service;
    controller = LearningPageController(
      cachedPage: (page) => source.cachedPage('topics/${widget.topicId}', {
        'page': '$page',
        'stage': stage,
      }),
      loadPage: (page) =>
          source.topic(widget.topicId, page: page, stage: stage),
      errorMessage: 'Chưa tải được chủ đề. Hãy thử lại.',
    )..addListener(_onPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    _warmup?.cancel();
    controller.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    setState(() {});
    final result = data;
    if (loading || result == null || error != null) return;
    final next = page + 1, filter = stage;
    final video = result.items.firstOrNull?['videoUrl'] as String? ?? '';
    final key = '$filter:$next:$video';
    if (_prefetched == key) return;
    _prefetched = key;
    _warmup?.cancel();
    final source = service;
    _warmup = Timer(const Duration(milliseconds: 700), () async {
      if (video.isNotEmpty) unawaited(prefetchSignVideo(video));
      if (next > result.pages) return;
      try {
        await source.topic(widget.topicId, page: next, stage: filter);
      } catch (_) {
        /* The requested page can retry normally. */
      }
    });
  }

  Future<void> load({int? page, bool force = false}) {
    if (force) service.invalidatePages();
    return controller.load(page: page);
  }

  Future<void> start() async {
    setState(() => saving = true);
    try {
      if (data?.enrolled != true) await service.start(widget.topicId);
      if (mounted) {
        await pushAppRoute(context, '/learn/topic/${widget.topicId}?study=1');
      }
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        toast(
          context,
          e is ApiException
              ? e.message
              : 'Chưa bắt đầu được chủ đề. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> openQuiz() async {
    if (saving) return;
    final mode = await chooseQuizMode(context);
    if (!mounted || mode == null) return;
    setState(() => saving = true);
    try {
      final quiz = mode == 'VIDEO_MATCH'
          ? await service.startMatchQuiz(widget.topicId)
          : await service.startQuiz(widget.topicId);
      if (!mounted) return;
      await pushAppRoute(context, '/learn/quiz/${quiz['_id']}');
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        toast(
          context,
          e is ApiException
              ? e.message
              : 'Chưa mở được bài ôn tập. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> rate(LearningRecord word, String selectedStage) async {
    if (saving || word['stage'] != 'LEARNING') return;
    setState(() {
      saving = true;
      ratingId = '${word['_id']}';
      ratingStage = selectedStage;
    });
    try {
      await service.rate('${word['_id']}', selectedStage);
      if (!mounted) return;
      controller.applyStage('${word['_id']}', selectedStage, filter: stage);
      toast(context, 'Đã lưu: ${learningLabels[selectedStage]}');
      unawaited(controller.load(background: true));
    } catch (_) {
      if (mounted) {
        toast(context, 'Chưa lưu được đánh giá. Hãy kiểm tra mạng và thử lại.');
      }
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
          ratingId = ratingStage = null;
        });
      }
    }
  }

  void changePage(int next) {
    load(page: next);
  }

  Widget wordCard(LearningRecord word, bool enrolled) => Padding(
    key: ValueKey('learning-word-${word['_id']}'),
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => showLearningWord(context, word),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SignPhoto(
                  word['thumbnailUrl'] as String?,
                  word: '${word['word']}',
                  width: 90,
                  height: 104,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${word['word']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${word['definition']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        enrolled
                            ? learningLabels[word['stage']] ?? 'Đang học'
                            : 'Xem ảnh & video →',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                key: ValueKey('learn-preview-${word['_id']}'),
                onPressed: () => showLearningWord(context, word),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Xem ký hiệu & ví dụ'),
              ),
              if (enrolled)
                TextButton.icon(
                  onPressed: () => pushAppRoute(
                    context,
                    '/learn/history?entryId=${word['_id']}',
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('Lịch sử từ này'),
                ),
            ],
          ),
          if (enrolled && word['stage'] == 'LEARNING') ...[
            const SizedBox(height: 8),
            const Text('Bạn nhớ từ này đến đâu?'),
            const SizedBox(height: 8),
            ActionGroup(
              children: [
                for (final value in ['REMEMBERED', 'REVIEW'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppButton(
                      learningLabels[value]!,
                      key: ValueKey('learn-rate-${word['_id']}-$value'),
                      secondary: true,
                      busy:
                          ratingId == '${word['_id']}' && ratingStage == value,
                      color: learningColors[value],
                      icon: value == 'REMEMBERED'
                          ? Icons.check_circle_outline
                          : Icons.refresh,
                      onPressed: saving ? null : () => rate(word, value),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final result = data;
    final words = result?.items ?? <LearningRecord>[];
    final enrolled = result?.enrolled == true;
    final isStudy = widget.study && enrolled;
    return AppPage(
      title: result?.topic['name'] as String? ?? 'Chủ đề ký hiệu',
      contentMaxWidth: 1120,
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: loading || saving ? null : () => load(force: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
      scroll: false,
      padding: EdgeInsets.zero,
      child: ListView(
        key: PageStorageKey('topic-${widget.topicId}-$stage-$page'),
        padding: pageInsets(context),
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: LinearProgressIndicator(),
            ),
          if (error != null) ...[
            Notice(error!),
            TextButton(onPressed: load, child: const Text('Thử lại')),
          ],
          if (result != null) ...[
            if (!isStudy) ...[
              if (words.isNotEmpty)
                SignPhoto(
                  words.first['thumbnailUrl'] as String?,
                  word: '${result.topic['name']}',
                  height: 170,
                ),
              const SizedBox(height: 18),
              Heading('${result.topic['name']}', size: 24),
              const SizedBox(height: 8),
              BodyText(
                '${result.summary['total'] ?? result.total} từ · ${result.topic['learnerCount'] ?? 0} người đã tham gia',
              ),
              const SizedBox(height: 14),
              const BodyText(
                'Xem ảnh và video, tự thực hành, rồi chọn mức độ ghi nhớ. Học chậm và đều theo nhịp của bạn.',
              ),
              const SizedBox(height: 18),
              AppButton(
                enrolled ? 'Tiếp tục học' : 'Bắt đầu học',
                key: const ValueKey('learn-start'),
                icon: Icons.play_arrow_rounded,
                busy: saving,
                onPressed: saving || result.total == 0 ? null : start,
              ),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.school_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Heading(
                      'Danh sách học · ${result.total} từ',
                      size: 18,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            if (enrolled) ...[
              LearningSummary(result.summary),
              const SizedBox(height: 16),
              StageFilters(
                value: stage,
                onChanged: saving
                    ? (_) {}
                    : (v) {
                        stage = v;
                        load(page: 1);
                      },
              ),
              const SizedBox(height: 18),
            ],
            if (words.isEmpty)
              const EmptyView(
                title: 'Không còn từ trong mục này',
                description: 'Chọn bộ lọc khác để tiếp tục học hoặc ôn tập.',
                icon: Icons.check_circle_outline,
              ),
            if (enrolled && stage == 'REVIEW' && words.isNotEmpty) ...[
              const Notice(
                'Chơi ghép cặp hoặc tự nhớ nghĩa ký hiệu. Mỗi lượt tối đa 10 từ; có gợi ý khi cần.',
              ),
              const SizedBox(height: 12),
              AppButton(
                'Bắt đầu quiz ôn tập',
                icon: Icons.quiz_outlined,
                busy: saving,
                onPressed: saving ? null : openQuiz,
              ),
              const SizedBox(height: 18),
            ],
            LayoutBuilder(
              builder: (context, size) {
                final columns =
                    size.maxWidth >= 860 &&
                        MediaQuery.textScalerOf(context).scale(1) < 1.5
                    ? 2
                    : 1;
                return Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (final word in words)
                      SizedBox(
                        width: (size.maxWidth - (columns - 1) * 16) / columns,
                        child: wordCard(word, enrolled),
                      ),
                  ],
                );
              },
            ),
            if (result.pages > 1)
              LearningPager(
                page: page,
                pages: result.pages,
                busy: saving,
                onPage: changePage,
              ),
            const SizedBox(height: 12),
            if (words.isNotEmpty)
              const Notice(
                'Học theo mẫu, tự nhớ nghĩa qua bài ôn tập và nhận gợi ý ôn từ AI sau khi hoàn tất.',
              ),
            if (isStudy)
              TextButton(
                onPressed: saving
                    ? null
                    : () => replaceAppRoute(
                        context,
                        '/learn/topic/${widget.topicId}',
                      ),
                child: const Text('Xem danh sách từ trong chủ đề'),
              ),
          ],
        ],
      ),
    );
  }
}
