import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collection_widgets.dart';

import '../../core/navigation.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';

String learningEventLabel(Object? kind) => switch (kind) {
  'TOPIC_STARTED' => 'Bắt đầu chủ đề',
  'SELF_RATED' => 'Tự đánh giá',
  'QUIZ_REVIEWED' => 'Ôn tập',
  _ => 'Trạng thái đã lưu',
};

class LearningHistoryScreen extends StatefulWidget {
  const LearningHistoryScreen({super.key, this.entryId});
  final String? entryId;
  @override
  State<LearningHistoryScreen> createState() => _LearningHistoryScreenState();
}

class _LearningHistoryScreenState extends State<LearningHistoryScreen> {
  final search = TextEditingController();
  int page = 1, request = 0, pageSize = 10;
  Timer? debounce;
  bool loading = true;
  String query = '';
  String? error;
  LearningPage? data;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) restoreSize();
    });
  }

  Future<void> restoreSize() async {
    if (!kIsWeb) {
      await load();
      return;
    }
    try {
      final saved = (await SharedPreferences.getInstance()).getInt(
        'learning.history.pageSize',
      );
      if (mounted && [10, 20, 50].contains(saved)) pageSize = saved!;
    } catch (_) {}
    if (mounted) await load();
  }

  Future<void> changeSize(int value) async {
    setState(() {
      pageSize = value;
      page = 1;
    });
    load();
    try {
      await (await SharedPreferences.getInstance()).setInt(
        'learning.history.pageSize',
        value,
      );
    } catch (_) {}
  }

  @override
  void didUpdateWidget(LearningHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId) {
      debounce?.cancel();
      page = 1;
      query = '';
      search.clear();
      load();
    }
  }

  @override
  void dispose() {
    request++;
    debounce?.cancel();
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
        pageSize: pageSize,
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
    debounce?.cancel();
    query = search.text.trim();
    page = 1;
    load();
  }

  String time(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return 'Chưa có thời gian';
    return DateFormat('dd/MM/yyyy · HH:mm').format(date);
  }

  Widget record(LearningRecord item) {
    final word = '${item['word'] ?? ''}';
    final kind = '${item['kind']}';
    final label = learningEventLabel(kind);
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
                onPressed: () => pushAppRoute(
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
        if (isDesktopLayout(context)) ...[
          const LearningTabs(selected: 4),
          const SizedBox(height: 24),
        ],
        const BodyText(
          'Xem các từ đã ghi nhận, thời điểm học và kết quả ôn tập, mới nhất trước.',
        ),
        const SizedBox(height: 16),
        if (isDesktopLayout(context))
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Text('Số mục mỗi trang: '),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: pageSize,
                items: [10, 20, 50]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: loading
                    ? null
                    : (n) {
                        if (n != null) changeSize(n);
                      },
              ),
            ],
          ),

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
          onChanged: (_) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 350), find);
          },
          onSubmitted: (_) => find(),
        ),
        if (widget.entryId != null)
          TextButton(
            onPressed: () => replaceAppRoute(context, '/learn/history'),
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
          if (isDesktopLayout(context) &&
              MediaQuery.textScalerOf(context).scale(1) < 1.6 &&
              data!.items.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    columnSpacing: 24,
                    dataRowMinHeight: 64,
                    dataRowMaxHeight: 88,
                    columns: const [
                      DataColumn(label: Text('Từ / Chủ đề')),
                      DataColumn(label: Text('Hoạt động')),
                      DataColumn(label: Text('Trạng thái')),
                      DataColumn(label: Text('Thời gian')),
                      DataColumn(label: Text('Chi tiết')),
                    ],
                    rows: [
                      for (final item in data!.items)
                        DataRow(
                          onSelectChanged:
                              item['entryId'] == null || widget.entryId != null
                              ? null
                              : (_) => pushAppRoute(
                                  context,
                                  '/learn/history?entryId=${item['entryId']}',
                                ),
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 200,
                                child: Text(
                                  '${item['word'] ?? item['topicName'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text(learningEventLabel(item['kind']))),
                            DataCell(
                              SignVoiceBadge(
                                learningLabels[item['stage']] ??
                                    'Chưa đánh giá',
                                color:
                                    learningColors[item['stage']] ??
                                    Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            DataCell(Text(time(item['createdAt']))),
                            DataCell(
                              item['entryId'] == null || widget.entryId != null
                                  ? const SizedBox()
                                  : TextButton.icon(
                                      label: const Text('Xem lịch sử từ'),
                                      onPressed: () => pushAppRoute(
                                        context,
                                        '/learn/history?entryId=${item['entryId']}',
                                      ),
                                      icon: const Icon(Icons.open_in_new),
                                    ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            )
          else
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
          if (data!.pages > 1)
            Text(
              '${data!.total} bản ghi · ${data!.pageSize} mục/trang',
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
