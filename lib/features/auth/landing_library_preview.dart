import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/public_sign_preview.dart';

import 'package:provider/provider.dart';

import '../../services/admin/admin_workspace_service.dart';
import '../learning/learning_widgets.dart';
import 'landing_motion.dart';

class LandingLibraryPreview extends StatefulWidget {
  const LandingLibraryPreview({
    super.key,
    required this.words,
    required this.loading,
    this.error,
  });
  final List<AdminRecord> words;
  final bool loading;
  final String? error;
  @override
  State<LandingLibraryPreview> createState() => _LandingLibraryPreviewState();
}

class _LandingLibraryPreviewState extends State<LandingLibraryPreview> {
  final search = TextEditingController();
  List<AdminRecord>? results;
  bool busy = false;
  String? error;
  int generation = 0, resultTotal = 0;
  Timer? debounce;
  String submittedQuery = '';
  void searchChanged(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), lookup);
  }

  void quickSearch(String word) {
    search.text = word;
    lookup();
  }

  Future<void> lookup() async {
    debounce?.cancel();
    final query = search.text.trim().toLowerCase();
    final service = context.read<AdminWorkspaceService?>();
    if (service == null) return;
    final request = ++generation;
    if (search.text.trim().isEmpty) {
      setState(() {
        results = null;
        busy = false;
        error = null;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await service.published(search: query, sort: '');
      if (!mounted || request != generation) return;
      int relevance(AdminRecord record) {
        final word = '${record['word']}'.toLowerCase();
        return word == query
            ? 0
            : word.startsWith(query)
            ? 1
            : word.contains(query)
            ? 2
            : 3;
      }

      final ranked = [...page.items]
        ..sort((a, b) => relevance(a).compareTo(relevance(b)));
      setState(() {
        results = ranked;
        resultTotal = page.total;
        submittedQuery = query;
      });
    } catch (_) {
      if (!mounted || request != generation) return;
      setState(() {
        error = 'Chưa thể tra cứu. Bạn hãy thử lại.';
        results = [];
      });
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> preview(AdminRecord record) async {
    await showDialog<void>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${record['word']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: LearningWordContent(record, showMeaning: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final words = (results ?? widget.words).take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('landing-search'),
          controller: search,
          textInputAction: TextInputAction.search,
          onChanged: searchChanged,
          onSubmitted: (_) => lookup(),
          decoration: InputDecoration(
            labelText: 'Thử một từ tiếng Việt',
            hintText: 'Ví dụ: chào, cảm ơn…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: search.text.isEmpty
                  ? 'Tra cứu ký hiệu'
                  : 'Xóa từ tìm kiếm',
              onPressed: () {
                if (search.text.isEmpty) {
                  lookup();
                } else {
                  search.clear();
                  lookup();
                }
              },
              icon: Icon(
                search.text.isEmpty ? Icons.arrow_forward : Icons.close,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final word in ['xin chào', 'cảm ơn', 'gia đình'])
              ActionChip(label: Text(word), onPressed: () => quickSearch(word)),
          ],
        ),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(
            results == null
                ? 'Từ nổi bật · ${words.length} mẫu để bắt đầu'
                : '${NumberFormat.decimalPattern('vi').format(resultTotal)} kết quả cho “$submittedQuery” · Xem trước ${words.length} mẫu',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 4,
          child: busy || widget.loading
              ? const LinearProgressIndicator()
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 12),
        if (error != null || results == null && widget.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              error ?? widget.error!,
              style: TextStyle(color: scheme.error),
            ),
          ),
        if (!busy &&
            !widget.loading &&
            error == null &&
            (results != null || widget.error == null) &&
            words.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Chưa tìm thấy ký hiệu. Thử một từ khác nhé.'),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final columns = MediaQuery.textScalerOf(context).scale(1) >= 1.5
                ? 1
                : box.maxWidth >= 900
                ? 3
                : box.maxWidth >= 560
                ? 2
                : 1;
            final width = (box.maxWidth - (columns - 1) * 16) / columns;
            final initial = widget.loading && words.isEmpty;
            return AnimatedOpacity(
              opacity: busy ? .5 : 1,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: busy,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    if (initial)
                      for (var i = 0; i < 6; i++)
                        SizedBox(
                          width: width,
                          height: 314,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(32),
                            child: const PublicPreviewSkeleton(),
                          ),
                        ),
                    for (final word in words)
                      SizedBox(
                        width: width,
                        child: LandingHover(
                          color: scheme.primary,
                          child: Material(
                            color: scheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                              side: BorderSide(color: scheme.outlineVariant),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Semantics(
                              button: true,
                              label: 'Xem ký hiệu ${word['word']}',
                              child: InkWell(
                                onTap: () => preview(word),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    PublicSignPreview(
                                      key: ValueKey(
                                        'landing-preview-${word['_id']}',
                                      ),
                                      word: word,
                                      height: 190,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${word['word']}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.open_in_new,
                                            size: 20,
                                          ),
                                        ],
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
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Chọn thẻ để xem mẫu và nguồn tư liệu. Rê chuột hoặc bấm phát để xem trước video tắt tiếng.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
