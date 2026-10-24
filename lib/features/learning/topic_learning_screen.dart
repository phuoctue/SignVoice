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
  int page = 1, index = 0, request = 0;
  bool loading = true, saving = false, reveal = false;
  String stage = 'ALL';
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
        index = 0;
        await load();
        return;
      }
      setState(() {
        data = result;
        if (index >= result.items.length) index = 0;
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

  Future<void> rate(String selectedStage) async {
    if (data == null || data!.items.isEmpty) return;
    final current = data!.items[index];
    setState(() => saving = true);
    try {
      await service.rate('${current['_id']}', selectedStage);
      if (!mounted) return;
      final previous = index;
      final lastOnPage = index == data!.items.length - 1;
      if (stage == 'ALL' && lastOnPage && page < data!.pages) {
        page++;
        index = 0;
      } else if (stage == 'ALL' && !lastOnPage) {
        index = previous + 1;
      } else {
        index = 0;
      }
      reveal = false;
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
    index = 0;
    reveal = false;
    load();
  }

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
                      'Lượt học · ${words.isEmpty ? 0 : (page - 1) * 10 + index + 1}/${result.total} từ',
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
                        index = 0;
                        page = 1;
                        reveal = false;
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
            if (isStudy && words.isNotEmpty) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Heading('${words[index]['word']}', size: 26),
                        ),
                        SignVoiceBadge(
                          learningLabels[words[index]['stage']] ?? 'Đang học',
                          color:
                              learningColors[words[index]['stage']] ??
                              const Color(0xFF2563EB),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    LearningWordContent(
                      words[index],
                      key: ValueKey(words[index]['_id']),
                      showMeaning: reveal,
                    ),
                    if (!reveal)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: AppButton(
                          'Xem nghĩa & ví dụ',
                          secondary: true,
                          icon: Icons.visibility_outlined,
                          onPressed: () => setState(() => reveal = true),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Heading('Bạn nhớ từ này đến đâu?', size: 17),
              const SizedBox(height: 10),
              const BodyText(
                'Chọn theo cảm nhận của bạn. Đánh giá được lưu vào tài khoản.',
              ),
              const SizedBox(height: 12),
              for (final entry in learningLabels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppButton(
                    entry.value,
                    secondary: true,
                    color: learningColors[entry.key],
                    icon: entry.key == 'REMEMBERED'
                        ? Icons.check_circle_outline
                        : entry.key == 'REVIEW'
                        ? Icons.refresh
                        : Icons.menu_book_outlined,
                    onPressed: saving ? null : () => rate(entry.key),
                  ),
                ),
              if (saving) const LinearProgressIndicator(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: saving || index == 0
                        ? null
                        : () => setState(() {
                            index--;
                            reveal = false;
                          }),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Từ trước'),
                  ),
                  TextButton.icon(
                    onPressed: saving || index >= words.length - 1
                        ? null
                        : () => setState(() {
                            index++;
                            reveal = false;
                          }),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Từ tiếp'),
                  ),
                ],
              ),
            ] else ...[
              for (final word in words)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
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
                                    ? learningLabels[word['stage']] ??
                                          'Đang học'
                                    : 'Xem ảnh & video →',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
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
