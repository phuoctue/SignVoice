import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'learning_page_controller.dart';
import 'learning_widgets.dart';
import 'personal_word_form.dart';
import 'learning_analysis_card.dart';

class LearningHub extends StatefulWidget {
  const LearningHub({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<LearningHub> createState() => _LearningHubState();
}

class _LearningHubState extends State<LearningHub> {
  late int tab = widget.initialTab;
  String query = '';
  bool coaching = false;
  bool analyzing = false;
  int analysisRequest = 0;
  String? analysisError;
  LearningRecord? analysis;
  late final LearningPageController controller;
  int get page => controller.page;
  String? get error => controller.error;
  bool get loading => controller.loading;
  LearningPage? get data => controller.data;
  LearningRecord? advice;
  final search = TextEditingController();
  Timer? _warmup;
  LearningService get service => context.read<LearningService>();
  @override
  void initState() {
    super.initState();
    final source = service;
    controller = LearningPageController(
      cachedPage: (page) => source.cachedPage(
        ['topics', 'progress', 'my-words'][tab],
        {'page': '$page', if (tab == 1) 'stage': 'ALL' else 'search': query},
      ),
      loadPage: (page) => switch (tab) {
        0 => source.topics(page: page, search: query),
        1 => source.progress(page: page),
        _ => source.myWords(page: page, search: query),
      },
      errorMessage: 'Chưa tải được nội dung. Hãy thử lại.',
    )..addListener(_onPageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    _warmup?.cancel();
    analysisRequest++;
    controller.dispose();
    search.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    setState(() {});
    if (controller.loading || controller.error != null) return;
    _warmup?.cancel();
    if (tab > 1) return;
    final source = service;
    _warmup = Timer(const Duration(milliseconds: 800), () async {
      try {
        if (tab == 0) {
          await source.progress();
        } else {
          await source.topics();
        }
      } catch (_) {
        /* Prefetch must never block navigation or show errors. */
      }
    });
  }

  Future<void> load({int? page, bool force = false, bool background = false}) {
    if (force) service.invalidatePages();
    analysisRequest++;
    setState(() {
      analysis = null;
      analysisError = null;
      analyzing = false;
    });
    return controller.load(page: page, background: background);
  }

  Future<void> openTopic(String id, {bool study = false}) async {
    await Navigator.pushNamed(
      context,
      '/learn/topic/$id${study ? '?study=1' : ''}',
    );
    if (mounted) load(background: true);
  }

  Future<void> coach() async {
    setState(() => coaching = true);
    try {
      final result = await service.coach();
      if (mounted) setState(() => advice = result);
    } catch (_) {
      if (mounted) {
        toast(context, 'Chưa lấy được gợi ý. Tiến độ của bạn vẫn được lưu.');
      }
    } finally {
      if (mounted) setState(() => coaching = false);
    }
  }

  Future<void> analyze() async {
    final current = ++analysisRequest;
    setState(() {
      analyzing = true;
      analysisError = null;
    });
    try {
      final result = await service.analyzeProgress();
      if (mounted && current == analysisRequest) {
        setState(() => analysis = result);
      }
    } catch (e) {
      if (mounted && current == analysisRequest) {
        setState(
          () => analysisError = e is ApiException
              ? e.message
              : 'Chưa phân tích được tiến độ. Dữ liệu học tập vẫn được lưu.',
        );
      }
    } finally {
      if (mounted && current == analysisRequest) {
        setState(() => analyzing = false);
      }
    }
  }

  Future<void> edit([LearningRecord? word]) async {
    if (await editPersonalWord(context, service, word: word) && mounted) {
      load(page: 1);
    }
  }

  Future<void> remove(LearningRecord word) async {
    if (!await confirm(
      context,
      title: 'Xóa “${word['word']}”?',
      message: 'Từ này sẽ được xóa khỏi danh sách riêng của bạn.',
    )) {
      return;
    }
    try {
      await service.deleteWord('${word['_id']}');
      if (mounted) load();
    } catch (_) {
      if (mounted) toast(context, 'Chưa xóa được từ. Hãy thử lại.');
    }
  }

  Widget topicCard(LearningRecord topic) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => openTopic('${topic['_id']}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SignPhoto(
            topic['imageUrl'] as String?,
            word: '${topic['name']}',
            width: 92,
            height: 112,
            fit: BoxFit.cover,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${topic['name']}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${topic['wordCount']} từ',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.people_outline, size: 16),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '${topic['learnerCount'] ?? 0} người đã tham gia',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  topic['enrolled'] == true
                      ? 'Đang trong lộ trình của bạn'
                      : 'Khám phá chủ đề →',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget progressCard(LearningRecord item) {
    final topic = LearningRecord.from(item['topic'] as Map);
    final counts = LearningRecord.from(item['summary'] as Map);
    final total = (counts['total'] as num? ?? 0).toInt();
    final remembered = (counts['remembered'] as num? ?? 0).toInt();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        onTap: () => openTopic('${topic['_id']}', study: true),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_stories_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${topic['name']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : remembered / total,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text('Đã nhớ $remembered / $total từ'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                SignVoiceBadge('${counts['learning'] ?? 0} đang học'),
                SignVoiceBadge(
                  '${counts['review'] ?? 0} ôn tập',
                  color: learningColors['REVIEW']!,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => openTopic('${topic['_id']}', study: true),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Tiếp tục học'),
            ),
          ],
        ),
      ),
    );
  }

  Widget personalCard(LearningRecord word) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => showLearningWord(context, word),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SignPhoto(
            word['imageUrl'] as String?,
            word: '${word['word']}',
            width: 76,
            height: 90,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${word['word']}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${word['definition']}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn từ ${word['word']}',
            onSelected: (v) => v == 'edit' ? edit(word) : remove(word),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa')),
              PopupMenuItem(value: 'delete', child: Text('Xóa từ')),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Từ điển ký hiệu',
    showBack: false,
    tabIndex: 1,
    actions: [
      IconButton(
        tooltip: 'Làm mới',
        onPressed: loading ? null : () => load(force: true),
        icon: const Icon(Icons.refresh),
      ),
      IconButton(
        tooltip: 'Ký hiệu yêu thích',
        onPressed: () => Navigator.pushNamed(context, 'S24'),
        icon: const Icon(Icons.favorite_border),
      ),
    ],
    scroll: false,
    padding: EdgeInsets.zero,
    child: ListView(
      key: PageStorageKey('learning-hub-$tab'),
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                  child: Semantics(
                    selected: tab == i,
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        if (tab != i) {
                          Navigator.pushReplacementNamed(
                            context,
                            '/learn?tab=$i',
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 3,
                        ),
                        decoration: BoxDecoration(
                          color: tab == i
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              [
                                Icons.explore_outlined,
                                Icons.school_outlined,
                                Icons.bookmark_add_outlined,
                              ][i],
                              size: 23,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              ['Khám phá', 'Đang học', 'Từ của tôi'][i],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: tab == i
                                    ? FontWeight.w700
                                    : FontWeight.w500,
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
        const SizedBox(height: 24),
        Heading(
          [
            'Học ký hiệu theo chủ đề',
            'Tiến độ học tập',
            'Bộ từ mang dấu ấn của bạn',
          ][tab],
          size: 23,
        ),
        const SizedBox(height: 8),
        BodyText(
          [
            'Chọn một chủ đề gần gũi. Xem ảnh, video và học từng nhóm 10 từ.',
            'Tự đánh giá sau mỗi từ. Những từ đã nhớ sẽ được nhắc ôn lại sau 3 ngày.',
            'Tự tạo từ, thêm ảnh ký hiệu và câu ví dụ. Danh sách được lưu riêng theo tài khoản.',
          ][tab],
        ),
        const SizedBox(height: 18),
        if (tab != 1)
          TextField(
            controller: search,
            decoration: InputDecoration(
              hintText: tab == 0
                  ? 'Tìm chủ đề bạn quan tâm...'
                  : 'Tìm trong từ của tôi...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Tìm kiếm',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () {
                  query = search.text.trim();
                  load(page: 1);
                },
              ),
            ),
            onSubmitted: (v) {
              query = v.trim();
              load(page: 1);
            },
          ),
        if (tab == 2) ...[
          const SizedBox(height: 12),
          AppButton('Tạo từ mới', icon: Icons.add, onPressed: () => edit()),
        ],
        if (tab == 1) ...[
          LearningSummary(data?.summary ?? {}),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/learn/history'),
            icon: const Icon(Icons.history),
            label: const Text('Lịch sử học tập'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/learn/insights'),
            icon: const Icon(Icons.bar_chart_outlined),
            label: const Text('Thống kê & mục tiêu'),
          ),
          const SizedBox(height: 16),
          AppButton(
            'Phân tích tiến độ cá nhân',
            icon: Icons.analytics_outlined,
            busy: analyzing,
            onPressed: analyzing || coaching || loading ? null : analyze,
          ),
          if (analysisError != null) ...[
            const SizedBox(height: 12),
            Notice(analysisError!),
          ],
          if (analysis != null) ...[
            const SizedBox(height: 12),
            LearningAnalysisCard(result: analysis!),
          ],
          const SizedBox(height: 16),
          AppButton(
            'Gợi ý ôn tập',
            icon: Icons.auto_awesome_outlined,
            secondary: true,
            busy: coaching,
            onPressed: coaching || analyzing ? null : coach,
          ),
          if (advice != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SignVoiceBadge(
                      advice!['source'] == 'lm-studio'
                          ? 'Gợi ý từ LM Studio'
                          : 'Lộ trình ôn tập cơ bản',
                    ),
                    const SizedBox(height: 12),
                    BodyText('${advice!['advice']}'),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 20),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (error != null) ...[
          Notice(error!),
          TextButton(onPressed: load, child: const Text('Thử lại')),
        ],
        if (!loading && error == null && data?.items.isEmpty == true)
          EmptyView(
            title: query.isNotEmpty
                ? 'Chưa tìm thấy kết quả'
                : [
                    'Chưa có chủ đề',
                    'Chưa có chủ đề trong mục này',
                    'Danh sách của bạn đang trống',
                  ][tab],
            description: query.isNotEmpty
                ? 'Thử từ khóa ngắn hơn hoặc tìm tên chủ đề khác.'
                : tab == 1
                ? 'Chọn một chủ đề trong Khám phá và bấm Bắt đầu học.'
                : tab == 2
                ? 'Bấm Tạo từ mới để thêm thẻ học đầu tiên.'
                : 'Các chủ đề có từ đã xuất bản sẽ xuất hiện tại đây.',
            icon: tab == 2
                ? Icons.bookmark_add_outlined
                : Icons.auto_stories_outlined,
            action: tab == 1
                ? TextButton(
                    onPressed: () =>
                        Navigator.pushReplacementNamed(context, '/learn?tab=0'),
                    child: const Text('Khám phá chủ đề'),
                  )
                : null,
          ),
        if (!loading && error == null && data != null) ...[
          for (final item in data!.items)
            switch (tab) {
              0 => topicCard(item),
              1 => progressCard(item),
              _ => personalCard(item),
            },
          if (data!.pages > 1)
            LearningPager(
              page: page,
              pages: data!.pages,
              onPage: (v) {
                load(page: v);
              },
            ),
          if (data!.total > 0)
            Text(
              tab == 2
                  ? '${data!.total} từ của bạn · 10 từ/trang'
                  : '${data!.total} chủ đề · 10 chủ đề/trang',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ],
    ),
  );
}
