import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../../services/api/api_exception.dart';
import '../../services/api/api_config.dart';
import '../speech/sign_sequence_panel.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String query = '', filter = 'Tất cả';
  Timer? debounce;
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() => AppScope.of(context)
      .loadHistory(
        search: query,
        direction: switch (filter) {
          'Ký hiệu' => 'SIGN_TO_SPEECH',
          'Giọng nói' => 'SPEECH_TO_TEXT',
          'Văn bản' => 'TEXT',
          _ => null,
        },
        favorite: filter == 'Yêu thích' ? true : null,
      )
      .then((_) {});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.history
        .where(
          (item) =>
              (item.content.toLowerCase().contains(query.toLowerCase()) &&
              (filter == 'Tất cả' ||
                  filter == 'Yêu thích' && item.favorite ||
                  filter == 'Ký hiệu' &&
                      item.direction == ConversationDirection.signToSpeech ||
                  filter == 'Giọng nói' &&
                      item.direction == ConversationDirection.speechToText ||
                  filter == 'Văn bản' &&
                      item.direction == ConversationDirection.text)),
        )
        .toList();
    return AppPage(
      title: 'Lịch sử hội thoại',
      showBack: false,
      tabIndex: 2,
      actions: [
        IconButton(
          onPressed: state.syncing ? null : _load,
          tooltip: 'Tải lại',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Tìm kiếm hội thoại...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              setState(() => query = value);
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 350), _load);
            },
            onSubmitted: (_) {
              debounce?.cancel();
              _load();
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in [
                'Tất cả',
                'Ký hiệu',
                'Giọng nói',
                'Văn bản',
                'Yêu thích',
              ])
                ChoiceChip(
                  label: Text(value),
                  selected: filter == value,
                  onSelected: (_) {
                    setState(() => filter = value);
                    _load();
                  },
                ),
            ],
          ),
          if (state.syncing) const LinearProgressIndicator(),
          if (state.error != null) ...[
            Notice(state.error!),
            TextButton(onPressed: _load, child: const Text('Thử lại')),
          ],
          if (items.isEmpty && !state.syncing && state.error == null)
            const EmptyView(
              title: 'Chưa có hội thoại phù hợp',
              description:
                  'Lưu nội dung từ một phiên giao tiếp để xem lại tại đây.',
            ),
          for (final item in items)
            Card(
              child: ListTile(
                title: Text(item.content),
                subtitle: Text('${item.label}\n${item.time}'),
                isThreeLine: true,
                onTap: () {
                  state.selectConversation(item);
                  openScreen(context, '/conversations/${item.id}');
                },
                trailing: IconButton(
                  tooltip: item.favorite ? 'Bỏ yêu thích' : 'Yêu thích',
                  icon: Icon(
                    item.favorite ? Icons.favorite : Icons.favorite_border,
                  ),
                  onPressed: () async {
                    final success = await state.toggleConversation(item);
                    if (!success && context.mounted) {
                      toast(context, state.error ?? 'Không lưu được thay đổi.');
                    }
                  },
                ),
              ),
            ),
          if (state.persisted && state.historyPage < state.historyPages)
            TextButton(
              onPressed: state.syncing
                  ? null
                  : () => state.loadHistory(more: true),
              child: const Text('Tải thêm hội thoại'),
            ),
        ],
      ),
    );
  }
}

class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({super.key, this.id});
  final String? id;
  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  bool loading = true, busy = false, missing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final state = AppScope.of(context),
        id = widget.id ?? AppScope.of(context).selectedHistoryId;
    setState(() {
      loading = true;
      missing = false;
    });
    final success = id != null && await state.selectHistoryId(id);
    if (mounted) {
      setState(() {
        loading = false;
        missing = !success;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context),
        item = AppScope.of(context).selectedConversation;
    if (loading) {
      return const AppPage(
        title: 'Chi tiết lịch sử',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (item == null || missing) {
      return AppPage(
        title: 'Chi tiết lịch sử',
        child: Column(
          children: [
            EmptyView(
              title: 'Không tìm thấy hội thoại',
              description:
                  state.error ?? 'Bản ghi không tồn tại hoặc đã bị xóa.',
            ),
            TextButton(onPressed: _load, child: const Text('Thử lại')),
          ],
        ),
      );
    }
    return AppPage(
      title: 'Chi tiết lịch sử',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SignVoiceBadge(item.label),
          const SizedBox(height: 20),
          SelectableText(
            item.content,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          BodyText(item.time),
          const SizedBox(height: 20),
          AppButton(
            'Phát giọng nói',
            icon: Icons.volume_up,
            onPressed: () {
              state.update(() {
                state.sentence
                  ..clear()
                  ..add(item.content);
              });
              openScreen(context, 'S14');
            },
          ),
          AppButton(
            'Sao chép',
            outlined: true,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: item.content));
              if (context.mounted) toast(context, 'Đã sao chép hội thoại.');
            },
          ),
          AppButton(
            item.favorite ? 'Bỏ yêu thích' : 'Thêm yêu thích',
            secondary: true,
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    final success = await state.toggleConversation(item);
                    if (context.mounted) {
                      setState(() => busy = false);
                      if (!success) {
                        toast(context, state.error ?? 'Không lưu được.');
                      }
                    }
                  },
          ),
          AppButton(
            'Xóa hội thoại',
            color: AppColors.red,
            secondary: true,
            onPressed: busy
                ? null
                : () async {
                    final epoch = state.accountEpoch;
                    if (!await confirm(
                      context,
                      title: 'Xóa hội thoại?',
                      message: 'Bản ghi này sẽ được xóa trên máy chủ.',
                    )) {
                      return;
                    }
                    if (!context.mounted ||
                        (state.persisted && !state.isCurrent(epoch))) {
                      return;
                    }
                    setState(() => busy = true);
                    final success = await state.removeConversation(item.id);
                    if (!context.mounted ||
                        (state.persisted && !state.isCurrent(epoch))) {
                      return;
                    }
                    setState(() => busy = false);
                    if (success) {
                      backOrHome(context);
                    } else {
                      toast(context, state.error ?? 'Không xóa được.');
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key, this.favoritesOnly = false});
  final bool favoritesOnly;
  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  String query = '';
  String sort = 'word_asc';
  String? categoryId, error;
  int page = 1, pages = 1, _request = 0;
  bool loading = true;
  Timer? _debounce;
  List<SignEntry> catalog = [];
  List<AdminRecord> topics = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _debounce?.cancel();
    final request = ++_request;
    final state = AppScope.of(context),
        epoch = AppScope.of(context).accountEpoch;
    bool current() =>
        mounted &&
        request == _request &&
        (!state.persisted || state.isCurrent(epoch));
    final service = context.read<AdminWorkspaceService>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final categories = (await service.activeCategories())
          .where((topic) => topic['wordCount'] != 0)
          .toList();
      if (!current()) return;
      if (categoryId != null &&
          !categories.any((topic) => '${topic['_id']}' == categoryId)) {
        categoryId = null;
        page = 1;
      }
      final result = widget.favoritesOnly
          ? await service.favoriteEntries(state.favorites)
          : await service.published(
              page: page,
              search: query,
              categoryId: categoryId,
              sort: sort,
            );
      if (!current()) return;
      if (current()) {
        setState(() {
          topics = categories;
          pages = result.pages;
          catalog = result.items
              .map(
                (item) => SignEntry(
                  '${item['word']}',
                  item['categoryId'] is Map
                      ? '${item['categoryId']['name']}'
                      : 'Danh mục',
                  '${item['definition']}',
                  '${item['usageExample'] ?? ''}',
                  id: '${item['_id']}',
                  videoUrl: item['videoUrl'] as String?,
                  thumbnailUrl: item['thumbnailUrl'] as String?,
                  imageUrls: List<String>.from(
                    item['imageUrls'] as List? ?? [],
                  ),
                  instructions: item['notes'] as String?,
                ),
              )
              .toList();
        });
      }
    } catch (e) {
      if (current()) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Không tải được từ điển. Hãy thử lại.',
        );
      }
    } finally {
      if (current()) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final entries = catalog
        .where(
          (s) =>
              !widget.favoritesOnly ||
              state.favorites.contains(s.favoriteKey) &&
                  (s.name.toLowerCase().contains(query.toLowerCase()) ||
                      s.meaning.toLowerCase().contains(query.toLowerCase())),
        )
        .toList();
    return AppPage(
      title: widget.favoritesOnly ? 'Ký hiệu yêu thích' : 'Từ điển ký hiệu',
      showBack: widget.favoritesOnly,
      tabIndex: widget.favoritesOnly ? null : 1,
      actions: widget.favoritesOnly
          ? null
          : [
              IconButton(
                tooltip: 'Làm mới',
                onPressed: loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Xem yêu thích',
                onPressed: () => openScreen(context, 'S24'),
                icon: const Icon(Icons.favorite_border),
              ),
            ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Tìm kiếm ký hiệu...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Tìm kiếm',
                onPressed: () {
                  page = 1;
                  _load();
                },
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
            onChanged: (v) {
              setState(() => query = v);
              _debounce?.cancel();
              page = 1;
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
            onSubmitted: (_) {
              page = 1;
              _load();
            },
          ),
          const SizedBox(height: 14),
          if (!widget.favoritesOnly) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(categoryId),
              initialValue: categoryId ?? '',
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: const InputDecoration(labelText: 'Chủ đề từ điển'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Tất cả chủ đề')),
                for (final topic in topics)
                  DropdownMenuItem(
                    value: '${topic['_id']}',
                    child: Text(
                      '${topic['name']}${topic['wordCount'] is num ? ' (${topic['wordCount']})' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: loading
                  ? null
                  : (value) {
                      setState(() {
                        categoryId = value == '' ? null : value;
                        page = 1;
                      });
                      _load();
                    },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey('dictionary-sort-$sort'),
              initialValue: sort,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Sắp xếp từ vựng',
                prefixIcon: Icon(Icons.sort_by_alpha),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'word_asc',
                  child: Text('Tăng dần (A–Z)'),
                ),
                DropdownMenuItem(
                  value: 'word_desc',
                  child: Text('Giảm dần (Z–A)'),
                ),
              ],
              onChanged: loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        sort = value;
                        page = 1;
                      });
                      _load();
                    },
            ),
            const SizedBox(height: 14),
          ],
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            TextButton(onPressed: _load, child: const Text('Thử lại')),
          ],
          if (entries.isEmpty && !loading && error == null)
            EmptyView(
              title: widget.favoritesOnly
                  ? 'Chưa có ký hiệu yêu thích'
                  : 'Không tìm thấy kết quả',
              description: widget.favoritesOnly
                  ? 'Nhấn vào trái tim trên ký hiệu để lưu tại đây.'
                  : 'Hãy thử từ khóa khác.',
              icon: widget.favoritesOnly ? Icons.favorite_border : Icons.search,
            ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent:
                  185 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.6),
            ),
            itemBuilder: (context, i) {
              final s = entries[i];
              final favorite = state.favorites.contains(s.favoriteKey);
              return AppCard(
                padding: EdgeInsets.zero,
                onTap: () {
                  state.selectSign(s);
                  openScreen(context, '/dictionary/${s.id}');
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        color:
                            (widget.favoritesOnly
                                    ? AppColors.red
                                    : AppColors.blue)
                                .withAlpha(15),
                        child: Stack(
                          children: [
                            if (s.thumbnailUrl != null)
                              Positioned.fill(
                                child: Image.network(
                                  ApiConfig.mediaUrl(s.thumbnailUrl!),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              )
                            else
                              const Center(
                                child: Icon(
                                  Icons.back_hand_outlined,
                                  size: 42,
                                  color: AppColors.blue,
                                ),
                              ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: IconButton(
                                tooltip: favorite
                                    ? 'Bỏ yêu thích'
                                    : 'Yêu thích',
                                onPressed: () async {
                                  if (state.guest) {
                                    openScreen(context, 'S06');
                                    return;
                                  }
                                  final success = await state.toggleSign(
                                    s.favoriteKey,
                                  );
                                  if (!success && context.mounted) {
                                    toast(
                                      context,
                                      state.error ??
                                          'Không lưu được yêu thích.',
                                    );
                                  }
                                },
                                icon: Icon(
                                  favorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: favorite
                                      ? AppColors.red
                                      : Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.category,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (pages > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Trang trước',
                  onPressed: !loading && page > 1
                      ? () {
                          page--;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$page / $pages'),
                IconButton(
                  tooltip: 'Trang sau',
                  onPressed: !loading && page < pages
                      ? () {
                          page++;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class SignDetailScreen extends StatefulWidget {
  const SignDetailScreen({super.key, this.entryId});
  final String? entryId;
  @override
  State<SignDetailScreen> createState() => _SignDetailScreenState();
}

class _SignDetailScreenState extends State<SignDetailScreen> {
  SignEntry? sign;
  String? error;
  bool loading = true, saving = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final state = AppScope.of(context),
        epoch = AppScope.of(context).accountEpoch;
    final id = widget.entryId ?? state.selectedSign.id;
    if (id == null) {
      setState(() {
        loading = false;
        error = 'Chưa chọn mục từ điển.';
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
      sign = null;
    });
    try {
      final record = state.service != null
          ? await state.service!.dictionaryEntry(id)
          : await context.read<AdminWorkspaceService>().publishedEntry(id);
      if (!mounted || (state.persisted && !state.isCurrent(epoch))) return;
      final item = SignEntry(
        '${record['word']}',
        record['categoryId'] is Map
            ? '${record['categoryId']['name']}'
            : 'Danh mục',
        '${record['definition']}',
        '${record['usageExample'] ?? ''}',
        id: '${record['_id']}',
        videoUrl: record['videoUrl'] as String?,
        thumbnailUrl: record['thumbnailUrl'] as String?,
        imageUrls: List<String>.from(record['imageUrls'] as List? ?? []),
        instructions: record['notes'] as String?,
      );
      state.selectSign(item);
      setState(() => sign = item);
    } catch (failure) {
      if (mounted && (!state.persisted || state.isCurrent(epoch))) {
        setState(
          () => error = failure is ApiException
              ? failure.message
              : 'Không tải được mục từ điển.',
        );
      }
    } finally {
      if (mounted && (!state.persisted || state.isCurrent(epoch))) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context), item = sign;
    if (loading) {
      return const AppPage(
        title: 'Chi tiết ký hiệu',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null || item == null) {
      return AppPage(
        title: 'Chi tiết ký hiệu',
        child: Column(
          children: [
            EmptyView(
              title: 'Không tìm thấy ký hiệu',
              description:
                  error ?? 'Mục từ đã bị xóa hoặc không còn được xuất bản.',
            ),
            TextButton(onPressed: _load, child: const Text('Thử lại')),
          ],
        ),
      );
    }
    final favorite = state.favorites.contains(item.favoriteKey);
    final uri = item.videoUrl == null
        ? null
        : Uri.tryParse(ApiConfig.mediaUrl(item.videoUrl!));
    final pictures = item.imageUrls.isNotEmpty
        ? item.imageUrls.map(ApiConfig.mediaUrl).toList()
        : <String>[
            if (item.thumbnailUrl != null)
              ApiConfig.mediaUrl(item.thumbnailUrl!),
          ];
    final mediaAvailable =
        uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty;
    return AppPage(
      title: item.name,
      actions: [
        IconButton(
          tooltip: favorite ? 'Bỏ yêu thích' : 'Yêu thích',
          onPressed: saving
              ? null
              : () async {
                  if (state.guest) {
                    openScreen(context, 'S06');
                    return;
                  }
                  setState(() => saving = true);
                  final success = await state.toggleSign(item.favoriteKey);
                  if (context.mounted) {
                    setState(() => saving = false);
                    if (!success) {
                      toast(
                        context,
                        state.error ?? 'Không lưu được yêu thích.',
                      );
                    }
                  }
                },
          icon: Icon(favorite ? Icons.favorite : Icons.favorite_border),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SignVoiceBadge(item.category),
          const SizedBox(height: 20),
          if (pictures.isNotEmpty)
            SignReferenceImages(urls: pictures, word: item.name)
          else
            const Icon(Icons.sign_language, size: 72),
          const SizedBox(height: 16),
          AppButton(
            mediaAvailable ? 'Mở video ký hiệu' : 'Chưa có video ký hiệu',
            icon: Icons.play_circle_outline,
            onPressed: mediaAvailable
                ? () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => SignVideoDialog(
                        items: [
                          {
                            'type': 'sign',
                            'text': item.name,
                            'videoUrl': uri.toString(),
                          },
                        ],
                        initialIndex: 0,
                      ),
                    );
                  }
                : null,
          ),
          const SizedBox(height: 20),
          const Heading('Ý nghĩa', size: 17),
          BodyText(item.meaning),
          const SizedBox(height: 20),
          const Heading('Hướng dẫn thực hiện', size: 17),
          BodyText(
            item.instructions?.isNotEmpty == true
                ? item.instructions!
                : 'Chưa có hướng dẫn chi tiết cho ký hiệu này.',
          ),
          if (item.example.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Heading('Ví dụ', size: 17),
            BodyText(item.example),
          ],
        ],
      ),
    );
  }
}
