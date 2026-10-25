import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';

class LearningHistoryScreen extends StatefulWidget {
  const LearningHistoryScreen({super.key, this.entryId});
  final String? entryId;
  @override
  State<LearningHistoryScreen> createState() => _LearningHistoryScreenState();
}

class _LearningHistoryScreenState extends State<LearningHistoryScreen> {
  final search = TextEditingController();
  int page = 1, request = 0;
  bool loading = true;
  String query = '';
  String? error;
  LearningPage? data;
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
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final current = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await context.read<LearningService>().history(
        page: page,
        search: query,
        entryId: widget.entryId,
      );
      if (!mounted || current != request) return;
      if (page > result.pages) {
        page = result.pages;
        await load();
        return;
      }
      setState(() => data = result);
    } catch (e) {
      if (mounted && current == request) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa tải được lịch sử. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  void find() {
    query = search.text.trim();
    page = 1;
    load();
  }

  String time(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return 'Chưa có thời gian';
    String two(int v) => '$v'.padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} · ${two(date.hour)}:${two(date.minute)}';
  }

  Widget record(LearningRecord item) {
    final word = '${item['word'] ?? ''}';
    final kind = '${item['kind']}';
    final label = switch (kind) {
      'TOPIC_STARTED' => 'Bắt đầu chủ đề',
      'SELF_RATED' => 'Tự đánh giá',
      'QUIZ_REVIEWED' => 'Ôn qua quiz camera',
      _ => 'Trạng thái đã lưu',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SignVoiceBadge(label),
            const SizedBox(height: 10),
            Text(
              word.isNotEmpty ? word : '${item['topicName']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (word.isNotEmpty) BodyText('${item['topicName']}'),
            if (item['stage'] != null)
              BodyText(learningLabels[item['stage']] ?? '${item['stage']}'),
            if (kind == 'QUIZ_REVIEWED') ...[
              BodyText(
                item['score'] == 10
                    ? 'Nhận diện khớp từ mục tiêu'
                    : 'Nhận diện chưa khớp từ mục tiêu',
              ),
              if (item['applied'] == false)
                const BodyText('Không cập nhật tiến độ.'),
            ],
            const SizedBox(height: 8),
            Text(
              time(item['createdAt']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (item['entryId'] != null && widget.entryId == null)
              TextButton(
                onPressed: () => Navigator.pushNamed(
                  context,
                  '/learn/history?entryId=${item['entryId']}',
                ),
                child: const Text('Lịch sử từ này'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Lịch sử học tập',
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
        const BodyText(
          'Xem các từ đã ghi nhận, thời điểm học và kết quả ôn tập, mới nhất trước.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Tìm từ hoặc chủ đề...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Tìm kiếm',
              onPressed: find,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
          onSubmitted: (_) => find(),
        ),
        if (widget.entryId != null)
          TextButton(
            onPressed: () =>
                Navigator.pushReplacementNamed(context, '/learn/history'),
            child: const Text('Xem tất cả lịch sử'),
          ),
        const SizedBox(height: 16),
        if (loading) const LinearProgressIndicator(),
        if (error != null) ...[
          Notice(error!),
          TextButton(onPressed: load, child: const Text('Thử lại')),
        ],
        if (!loading && error == null && data?.items.isEmpty == true)
          EmptyView(
            title: query.isEmpty
                ? 'Chưa có lịch sử học tập'
                : 'Chưa tìm thấy bản ghi',
            description:
                'Các lượt học và ôn tập sẽ xuất hiện ở đây khi được ghi nhận.',
            icon: Icons.history,
          ),
        if (!loading && error == null && data != null) ...[
          for (final item in data!.items) record(item),
          if (data!.pages > 1)
            LearningPager(
              page: page,
              pages: data!.pages,
              onPage: (value) {
                page = value;
                load();
              },
            ),
          Text(
            '${data!.total} bản ghi · 10 mục/trang',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const BodyText(
            'Trạng thái đã lưu là lần cập nhật gần nhất của từ chưa có nhật ký từng lượt.',
          ),
        ],
      ],
    ),
  );
}
