import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_provider.dart';
import '../../screens/admin/admin_ui.dart';
import '../../services/media/managed_media.dart';
import '../../widgets/public_sign_preview.dart';
import '../../widgets/public_catalog_page.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../../widgets/web_history_table.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../../services/api/api_exception.dart';
import '../../services/api/api_config.dart';
import '../speech/sign_sequence_panel.dart';
import '../learning/collection_widgets.dart';

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

  Future<void> _load({int? page, int? pageSize}) =>
      AppScope.of(context)
          .loadHistory(
            pageNumber: page,
            pageSize: pageSize,
            search: query,
            direction: switch (filter) {
              'Ký hiệu' => 'SIGN_TO_SPEECH',
              'Giọng nói' => 'SPEECH_TO_TEXT',
              'Văn bản' => 'TEXT',
              _ => null,
            },
            favorite: filter == 'Yêu thích' ? true : null,
          )
          .then((_) {
            if (mounted) setState(() {});
          });
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final desktopTable =
        isDesktopLayout(context) &&
        MediaQuery.textScalerOf(context).scale(1) < 1.6;
    final items = state.history
        .where(
          (item) =>
              (state.persisted ||
              item.content.toLowerCase().contains(query.toLowerCase()) &&
                  (filter == 'Tất cả' ||
                      filter == 'Yêu thích' && item.favorite ||
                      filter == 'Ký hiệu' &&
                          item.direction ==
                              ConversationDirection.signToSpeech ||
                      filter == 'Giọng nói' &&
                          item.direction ==
                              ConversationDirection.speechToText ||
                      filter == 'Văn bản' &&
                          item.direction == ConversationDirection.text)),
        )
        .toList();
    final clearAction = PopupMenuButton<String>(
      tooltip: 'Quản lý hội thoại',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_sweep_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              'Xóa tất cả hội thoại',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'clear',
          enabled:
              !state.syncing &&
              items.isNotEmpty &&
              query.trim().isEmpty &&
              filter == 'Tất cả' &&
              state.historySearch.isEmpty &&
              state.historyDirection == null &&
              state.historyFavorite == null,
          child: Text(
            query.trim().isNotEmpty || filter != 'Tất cả'
                ? 'Bỏ bộ lọc để xóa tất cả'
                : 'Xóa tất cả hội thoại',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
      onSelected: (_) async {
        final total = state.persisted
            ? state.historyTotal
            : state.history.length;
        if (await confirm(
          context,
          title: 'Xóa toàn bộ $total hội thoại?',
          message:
              'Thao tác này xóa tất cả $total hội thoại trong tài khoản, kể cả các trang khác. Không thể hoàn tác.',
          confirmLabel: 'Xóa $total hội thoại',
          destructive: true,
        )) {
          if (!context.mounted) return;
          final success = await state.clearHistory();
          if (mounted) {
            setState(() {});
            if (!success && context.mounted) {
              toast(context, state.error ?? 'Chưa xóa được lịch sử.');
            }
          }
        }
      },
    );
    return AppPage(
      title: 'Hội thoại',
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
          if (desktopTable && items.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WebHistoryTable(
                  items: items,
                  total: state.persisted ? state.historyTotal : items.length,
                  onOpen: (item) {
                    state.selectConversation(item);
                    openScreen(context, '/conversations/${item.id}');
                  },
                  onFavorite: (item) async {
                    final success = await state.toggleConversation(item);
                    if (!mounted) return;
                    setState(() {});
                    if (!success && context.mounted) {
                      toast(context, state.error ?? 'Không lưu được thay đổi.');
                    }
                  },
                  onDelete: (item) async {
                    if (await confirm(
                      context,
                      title: 'Xóa hội thoại?',
                      destructive: true,
                      message: 'Hội thoại này sẽ được xóa khỏi lịch sử.',
                    )) {
                      if (!context.mounted) return;
                      if (!await state.removeConversation(item.id) &&
                          context.mounted) {
                        toast(
                          context,
                          state.error ?? 'Chưa xóa được hội thoại.',
                        );
                      }
                      if (mounted) setState(() {});
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Hiển thị'),
                      DropdownButton<int>(
                        value: state.historyPageSize,
                        items: [10, 20, 50]
                            .map(
                              (n) =>
                                  DropdownMenuItem(value: n, child: Text('$n')),
                            )
                            .toList(),
                        onChanged: state.syncing
                            ? null
                            : (n) => _load(page: 1, pageSize: n),
                      ),
                      if (state.persisted && state.historyPages > 1)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Trang trước',
                              onPressed: state.syncing || state.historyPage <= 1
                                  ? null
                                  : () => _load(page: state.historyPage - 1),
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text(
                              'Trang ${state.historyPage}/${state.historyPages}',
                            ),
                            IconButton(
                              tooltip: 'Trang sau',
                              onPressed:
                                  state.syncing ||
                                      state.historyPage >= state.historyPages
                                  ? null
                                  : () => _load(page: state.historyPage + 1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            )
          else
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: item.favorite ? 'Bỏ yêu thích' : 'Yêu thích',
                        icon: Icon(
                          item.favorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
                        onPressed: () async {
                          final success = await state.toggleConversation(item);
                          if (mounted) setState(() {});
                          if (!success && context.mounted) {
                            toast(
                              context,
                              state.error ?? 'Không lưu được thay đổi.',
                            );
                          }
                        },
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Thao tác hội thoại',
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Xóa hội thoại'),
                          ),
                        ],
                        onSelected: (_) async {
                          if (await confirm(
                                context,
                                title: 'Xóa hội thoại?',
                                message:
                                    'Hội thoại này sẽ được xóa khỏi lịch sử.',
                                destructive: true,
                              ) &&
                              context.mounted) {
                            await state.removeConversation(item.id);
                            if (mounted) setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
          if (!desktopTable &&
              state.persisted &&
              state.historyPage < state.historyPages)
            TextButton(
              onPressed: state.syncing
                  ? null
                  : () => state.loadHistory(more: true),
              child: const Text('Tải thêm hội thoại'),
            ),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerRight, child: clearAction),
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
        title: 'Chi tiết hội thoại',
        contentMaxWidth: 900,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (item == null || missing) {
      return AppPage(
        title: 'Chi tiết hội thoại',
        contentMaxWidth: 900,
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
      title: 'Chi tiết hội thoại',
      contentMaxWidth: 900,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SignVoiceBadge(item.label),
            ),
            const SizedBox(height: 20),
            SelectableText(
              item.content,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 14),
            BodyText(item.time),
            const SizedBox(height: 20),
            ActionGroup(
              children: [
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
                    if (context.mounted) {
                      toast(context, 'Đã sao chép hội thoại.');
                    }
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
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
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
                        destructive: true,
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
  String query = '', sort = '';
  String? categoryId, error;
  int page = 1, pages = 1, total = 0, _request = 0;
  bool loading = true, _categoriesLoaded = false;
  Timer? _debounce;
  final search = TextEditingController(), pageInput = TextEditingController();
  final searchFocus = FocusNode();
  final gridTop = GlobalKey();
  List<AdminRecord> catalog = [], topics = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    search.dispose();
    pageInput.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _debounce?.cancel();
    final request = ++_request, state = AppScope.of(context);
    final epoch = state.accountEpoch;
    bool current() =>
        mounted &&
        request == _request &&
        (!state.persisted || state.accountId == null || state.isCurrent(epoch));
    final service = context.read<AdminWorkspaceService>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!_categoriesLoaded) {
        final categories = (await service.activeCategories())
            .where((topic) => topic['wordCount'] != 0)
            .toList();
        if (!current()) return;
        topics = categories;
        _categoriesLoaded = true;
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
      primeImagePreviews(result.items);
      setState(() {
        total = result.total;
        pages = result.pages.clamp(1, 1000000);
        catalog = result.items;
        pageInput.text = '$page';
      });
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

  void _search(String value, {bool immediately = false}) {
    _request++;
    setState(() {
      query = value;
      page = 1;
      loading = true;
      error = null;
    });
    _debounce?.cancel();
    if (immediately) {
      _load();
    } else {
      _debounce = Timer(const Duration(milliseconds: 350), _load);
    }
  }

  SignEntry _sign(AdminRecord item) => SignEntry(
    '${item['word']}',
    item['categoryId'] is Map
        ? '${item['categoryId']['name']}'
        : 'Ký hiệu công khai',
    '${item['definition'] ?? ''}',
    '${item['usageExample'] ?? ''}',
    id: '${item['_id']}',
    videoUrl: item['videoUrl'] as String?,
    thumbnailUrl: item['thumbnailUrl'] as String?,
    imageUrls: List<String>.from(item['imageUrls'] as List? ?? []),
    instructions: item['notes'] as String?,
  );
  Future<void> _favorite(SignEntry sign) async {
    final state = AppScope.of(context), auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated ||
        auth.user?.isGuest == true ||
        state.guest ||
        state.persisted && state.accountId == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 460),
          title: const Text('Lưu ký hiệu yêu thích'),
          content: const Text(
            'Đăng nhập để lưu ký hiệu yêu thích và xem lại trên các thiết bị của bạn.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Để sau'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                openScreen(
                  this.context,
                  authLocation(returnRoute: '/dictionary/browse'),
                );
              },
              child: const Text('Đăng nhập'),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await state.toggleSign(sign.favoriteKey);
    if (!ok && mounted) {
      toast(context, state.error ?? 'Không lưu được yêu thích.');
    }
  }

  void _changePage(int value) {
    if (loading || value < 1 || value > pages || value == page) {
      pageInput.text = '$page';
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => page = value);
    _load().then((_) {
      if (mounted && gridTop.currentContext != null) {
        Scrollable.ensureVisible(
          gridTop.currentContext!,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme, state = AppScope.of(context);
    final entries = widget.favoritesOnly
        ? catalog.where((record) {
            final sign = _sign(record);
            return state.favorites.contains(sign.favoriteKey) &&
                (sign.name.toLowerCase().contains(query.toLowerCase()) ||
                    sign.meaning.toLowerCase().contains(query.toLowerCase()));
          }).toList()
        : catalog;
    final content = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.slash): () =>
            searchFocus.requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.favoritesOnly
                          ? 'Ký hiệu yêu thích'
                          : 'Từ điển ký hiệu',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.favoritesOnly
                          ? 'Các mẫu ký hiệu bạn đã lưu.'
                          : 'Xem rõ động tác, khám phá từ theo chủ đề.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Làm mới'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, box) {
                final compact =
                    box.maxWidth < 850 ||
                    MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                final field = TextField(
                  key: const ValueKey('dictionary-search'),
                  controller: search,
                  focusNode: searchFocus,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Tìm kiếm ký hiệu',
                    hintText: 'Nhập từ tiếng Việt',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? const Tooltip(
                            message: 'Phím / để tìm kiếm',
                            child: Icon(Icons.keyboard, size: 20),
                          )
                        : IconButton(
                            tooltip: 'Xóa tìm kiếm',
                            onPressed: () {
                              search.clear();
                              _search('', immediately: true);
                              searchFocus.requestFocus();
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: _search,
                  onSubmitted: (value) => _search(value, immediately: true),
                );
                final category = AdminSelectField(
                  label: 'Chủ đề',
                  value: categoryId ?? '',
                  searchable: true,
                  options: {
                    '': 'Tất cả chủ đề',
                    for (final topic in topics)
                      '${topic['_id']}': '${topic['name']}',
                  },
                  onChanged: loading
                      ? null
                      : (value) {
                          setState(() {
                            categoryId = value.isEmpty ? null : value;
                            page = 1;
                          });
                          _load();
                        },
                );
                final sorting = AdminSelectField(
                  label: 'Sắp xếp',
                  value: sort,
                  options: const {
                    '': 'Mới xuất bản',
                    'word_asc': 'Tên: A–Z',
                    'word_desc': 'Tên: Z–A',
                  },
                  onChanged: loading
                      ? null
                      : (value) {
                          setState(() {
                            sort = value;
                            page = 1;
                          });
                          _load();
                        },
                );
                if (widget.favoritesOnly) return field;
                if (!compact) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: field),
                      const SizedBox(width: 14),
                      Expanded(flex: 3, child: category),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: sorting),
                    ],
                  );
                }
                final mobileFilters =
                    box.maxWidth < 600 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.5;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field,
                    const SizedBox(height: 14),
                    if (mobileFilters)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: category),
                          const SizedBox(width: 10),
                          Expanded(child: sorting),
                        ],
                      )
                    else ...[
                      category,
                      const SizedBox(height: 14),
                      sorting,
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (!widget.favoritesOnly)
              LayoutBuilder(
                builder: (context, box) {
                  final topicsForChips =
                      ([...topics]..sort((a, b) {
                            int rank(AdminRecord topic) =>
                                RegExp(
                                  'giao tiếp|gia đình|cảm xúc|đời sống',
                                  caseSensitive: false,
                                ).hasMatch('${topic['name']}')
                                ? 0
                                : 1;
                            return rank(a).compareTo(rank(b));
                          }))
                          .take(5)
                          .toList();
                  Widget chip(AdminRecord topic) => ChoiceChip(
                    label: Text('${topic['name']}'),
                    selected: categoryId == '${topic['_id']}',
                    onSelected: loading
                        ? null
                        : (selected) {
                            setState(() {
                              categoryId = selected ? '${topic['_id']}' : null;
                              page = 1;
                            });
                            _load();
                          },
                  );
                  final horizontal =
                      box.maxWidth < 600 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.5;
                  if (horizontal) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          for (var i = 0; i < topicsForChips.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            chip(topicsForChips[i]),
                          ],
                        ],
                      ),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final topic in topicsForChips) chip(topic)],
                  );
                },
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 4,
              child: loading
                  ? const LinearProgressIndicator()
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            Text(
              loading && catalog.isEmpty
                  ? 'Đang mở thư viện…'
                  : '${total == 0 ? 0 : (page - 1) * 20 + 1}–${((page - 1) * 20 + entries.length).clamp(0, total)} / ${NumberFormat.decimalPattern('vi').format(total)} ký hiệu${query.isNotEmpty ? ' · “$query”' : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Notice(error!, color: scheme.error),
              ),
            if (entries.isEmpty && !loading && error == null)
              EmptyView(
                title: widget.favoritesOnly
                    ? 'Chưa có ký hiệu yêu thích'
                    : 'Không tìm thấy ký hiệu',
                description: widget.favoritesOnly
                    ? 'Nhấn vào trái tim để lưu ký hiệu tại đây.'
                    : 'Thử từ khóa hoặc chủ đề khác.',
                icon: widget.favoritesOnly
                    ? Icons.favorite_border
                    : Icons.search,
              ),
            if (loading && entries.isEmpty)
              LayoutBuilder(
                builder: (context, box) {
                  final count = box.maxWidth >= 900
                      ? 4
                      : box.maxWidth >= 600
                      ? 2
                      : 1;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (var i = 0; i < count * 2; i++)
                        SizedBox(
                          width: (box.maxWidth - (count - 1) * 16) / count,
                          height: 280,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: const PublicPreviewSkeleton(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            if (entries.isNotEmpty)
              AnimatedOpacity(
                key: gridTop,
                opacity: loading ? .45 : 1,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: loading,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final columns = scale >= 1.5
                          ? (box.maxWidth >= 900 ? 2 : 1)
                          : box.maxWidth >= 1050
                          ? 4
                          : box.maxWidth >= 720
                          ? 3
                          : box.maxWidth >= 500
                          ? 2
                          : 1;
                      final width =
                              (box.maxWidth - (columns - 1) * 16) / columns,
                          imageHeight = width * .625;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: entries.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          mainAxisExtent:
                              imageHeight + 44 + 112 * scale.clamp(1, 2.5),
                        ),
                        itemBuilder: (context, i) {
                          final record = entries[i],
                              sign = _sign(record),
                              favorite = state.favorites.contains(
                                sign.favoriteKey,
                              );
                          return Semantics(
                            button: true,
                            label:
                                'Ký hiệu: ${sign.name}, chủ đề ${sign.category}',
                            child: Material(
                              color: scheme.surfaceContainerLow,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                                side: BorderSide(color: scheme.outlineVariant),
                              ),
                              child: InkWell(
                                onTap: () {
                                  state.selectSign(sign);
                                  openScreen(context, '/dictionary/${sign.id}');
                                },
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    PublicSignPreview(
                                      key: ValueKey('preview-${sign.id}'),
                                      word: record,
                                      height: imageHeight,
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          10,
                                          8,
                                          10,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    sign.name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    sign.category,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: scheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: favorite
                                                  ? 'Bỏ yêu thích ${sign.name}'
                                                  : 'Yêu thích ${sign.name}',
                                              onPressed: () => _favorite(sign),
                                              icon: Icon(
                                                favorite
                                                    ? Icons.favorite
                                                    : Icons.favorite_border,
                                                color: favorite
                                                    ? scheme.error
                                                    : scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            if (pages > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 12,
                  children: [
                    IconButton(
                      tooltip: 'Trang trước',
                      onPressed: !loading && page > 1
                          ? () => _changePage(page - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    for (final number in {
                      1,
                      if (page > 2) page - 1,
                      page,
                      if (page < pages - 1) page + 1,
                      pages,
                    }.toList()..sort())
                      TextButton(
                        onPressed: loading ? null : () => _changePage(number),
                        style: TextButton.styleFrom(
                          backgroundColor: number == page
                              ? scheme.primaryContainer
                              : null,
                        ),
                        child: Text('$number'),
                      ),
                    IconButton(
                      tooltip: 'Trang sau',
                      onPressed: !loading && page < pages
                          ? () => _changePage(page + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        key: const ValueKey('dictionary-page'),
                        controller: pageInput,
                        enabled: !loading,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.go,
                        decoration: const InputDecoration(
                          labelText: 'Đến trang',
                          isDense: true,
                        ),
                        onSubmitted: (value) =>
                            _changePage(int.tryParse(value) ?? page),
                      ),
                    ),
                    Text('/ $pages'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (!widget.favoritesOnly &&
        !context.watch<AuthProvider>().isAuthenticated) {
      return PublicCatalogPage(title: 'Từ điển ký hiệu', child: content);
    }
    return AppPage(
      title: widget.favoritesOnly ? 'Ký hiệu yêu thích' : 'Từ điển ký hiệu',
      preferDesktop: true,
      showBack: true,
      tabIndex: widget.favoritesOnly ? null : 1,
      child: content,
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
      if (!mounted ||
          (state.persisted &&
              state.accountId != null &&
              !state.isCurrent(epoch))) {
        return;
      }
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
        if (item.id != null)
          IconButton(
            tooltip: 'Thêm vào bộ sưu tập',
            onPressed: () async {
              final saved = await pushAppRoute(
                context,
                '/collections/save/${item.id}',
              );
              if (context.mounted && saved == true) {
                toast(context, 'Đã lưu ký hiệu vào bộ sưu tập.');
              }
            },
            icon: const Icon(Icons.playlist_add),
          ),
        IconButton(
          tooltip: favorite ? 'Bỏ yêu thích' : 'Yêu thích',
          onPressed: saving
              ? null
              : () async {
                  if (state.guest ||
                      state.persisted && state.accountId == null) {
                    openScreen(
                      context,
                      authLocation(
                        register: true,
                        returnRoute:
                            '/dictionary/${widget.entryId ?? state.selectedSign.id}',
                      ),
                    );
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
          if (item.id != null)
            TextButton.icon(
              onPressed: () => editSignNote(context, item.id!),
              icon: const Icon(Icons.edit_note),
              label: const Text('Ghi chú riêng'),
            ),
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
