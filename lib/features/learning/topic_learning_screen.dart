import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';

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
  LearningPage? data;
  int page = 1, request = 0;
  bool loading = true, saving = false;
  late String stage = widget.study ? 'LEARNING' : 'ALL';
  String? error;
  LearningService get service => context.read<LearningService>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    request++;
    super.dispose();
  }

  Future<void> load() async {
    final current = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await service.topic(
        widget.topicId,
        page: page,
        stage: stage,
      );
      if (!mounted || current != request) return;
      if (page > result.pages) {
        page = result.pages;
        await load();
        return;
      }
      setState(() {
        data = result;
      });
    } catch (e) {
      if (mounted && current == request) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa tải được chủ đề. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  Future<void> start() async {
    setState(() => saving = true);
    try {
      await service.start(widget.topicId);
      if (mounted) {
        await Navigator.pushNamed(
          context,
          '/learn/topic/${widget.topicId}?study=1',
        );
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
    setState(() => saving = true);
    try {
      final quiz = await service.startQuiz(widget.topicId);
      if (!mounted) return;
      await Navigator.pushNamed(context, '/learn/quiz/${quiz['_id']}');
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
    setState(() => saving = true);
    try {
      await service.rate('${word['_id']}', selectedStage);
      if (!mounted) return;
      await load();
      if (mounted) toast(context, 'Đã lưu: ${learningLabels[selectedStage]}');
    } catch (_) {
      if (mounted) {
        toast(context, 'Chưa lưu được đánh giá. Hãy kiểm tra mạng và thử lại.');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void changePage(int next) {
    page = next;
    load();
  }

  Widget wordCard(LearningRecord word, bool enrolled) => Padding(
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
          TextButton.icon(
            onPressed: () => showLearningWord(context, word),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Xem ký hiệu & ví dụ'),
          ),
          if (enrolled && word['stage'] == 'LEARNING') ...[
            const SizedBox(height: 8),
            const Text('Bạn nhớ từ này đến đâu?'),
            const SizedBox(height: 8),
            for (final value in ['REMEMBERED', 'REVIEW'])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppButton(
                  learningLabels[value]!,
                  secondary: true,
                  color: learningColors[value],
                  icon: value == 'REMEMBERED'
                      ? Icons.check_circle_outline
                      : Icons.refresh,
                  onPressed: saving ? null : () => rate(word, value),
                ),
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
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: loading || saving ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          if (!loading && error == null && result != null) ...[
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
                        page = 1;
                        load();
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
                'Ôn theo quiz, tối đa 10 câu mỗi lượt. LM Studio đánh giá nghĩa hoặc câu ví dụ; kết quả không chấm động tác ký hiệu.',
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
            for (final word in words) wordCard(word, enrolled),
            if (result.pages > 1)
              LearningPager(
                page: page,
                pages: result.pages,
                busy: saving,
                onPage: changePage,
              ),
            const SizedBox(height: 12),
            const Notice(
              'Tự thực hành theo ảnh/video tham khảo. Tiến độ phản ánh đánh giá của chính bạn; LM Studio chỉ gợi ý ôn tập.',
            ),
            if (isStudy)
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pushReplacementNamed(
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
