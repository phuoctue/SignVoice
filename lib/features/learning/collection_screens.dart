import 'dart:async';

import '../../core/navigation.dart';
import '../../widgets/ui.dart' as common;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/auth_provider.dart';
import '../../services/api/api_config.dart';
import '../../services/api/api_client.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import '../../widgets/public_catalog_page.dart';
import '../auth/auth_screens.dart';
import 'collection_widgets.dart';
import 'learning_widgets.dart';
import 'personal_word_form.dart';

abstract class _CollectionPageState<T extends StatefulWidget> extends State<T> {
  LearningRecord? data;
  String? error, action;
  bool loading = true;
  int page = 1, request = 0;
  String query = '';
  final search = TextEditingController();
  Timer? searchDebounce;
  LearningService get service => context.read<LearningService>();
  String get path;
  List<LearningRecord> get items => (data?['items'] as List? ?? [])
      .map((row) => LearningRecord.from(row as Map))
      .toList();
  int get pages => (data?['pagination']?['pages'] as num? ?? 1).toInt();
  int get total => (data?['pagination']?['total'] as num? ?? 0).toInt();
  @override
  void initState() {
    super.initState();
    ApiClient.instance.libraryChanged.addListener(_libraryUpdated);
    data = service.cachedCollection(path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  @override
  void dispose() {
    ApiClient.instance.libraryChanged.removeListener(_libraryUpdated);
    request++;
    searchDebounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _libraryUpdated() {
    if (mounted) load();
  }

  Future<void> load({int? nextPage, bool force = false}) async {
    if (force) service.invalidatePages();
    final current = ++request;
    setState(() {
      page = nextPage ?? page;
      loading = true;
      error = null;
    });
    try {
      final value = await service.collectionRead(
        path,
        page: page,
        search: query,
      );
      if (mounted && current == request) setState(() => data = value);
    } catch (e) {
      if (mounted && current == request) {
        setState(() => error = collectionError(e));
      }
    } finally {
      if (mounted && current == request) setState(() => loading = false);
    }
  }

  Future<void> perform(String key, Future<void> Function() operation) async {
    if (!mounted || action != null) return;
    setState(() => action = key);
    try {
      await operation();
    } catch (e) {
      if (mounted) toast(context, collectionError(e));
    } finally {
      if (mounted) setState(() => action = null);
    }
  }

  Widget searchField(String label) => TextField(
    controller: search,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: label,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: IconButton(
        tooltip: 'Tìm kiếm',
        onPressed: () {
          searchDebounce?.cancel();
          query = search.text.trim();
          load(nextPage: 1);
        },
        icon: const Icon(Icons.arrow_forward),
      ),
    ),
    onChanged: (value) {
      searchDebounce?.cancel();
      searchDebounce = Timer(const Duration(milliseconds: 350), () {
        if (mounted) {
          query = value.trim();
          load(nextPage: 1);
        }
      });
    },
    onSubmitted: (value) {
      searchDebounce?.cancel();
      query = value.trim();
      load(nextPage: 1);
    },
  );
  Widget status({required String empty, required String explanation}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: LinearProgressIndicator(),
        ),
      if (error != null) ...[
        Notice(error!),
        TextButton(
          onPressed: () => load(force: true),
          child: const Text('Thử lại'),
        ),
      ],
      if (!loading && error == null && items.isEmpty)
        EmptyView(
          title: empty,
          description: explanation,
          icon: Icons.collections_bookmark_outlined,
        ),
      if (pages > 1)
        LearningPager(
          page: page,
          pages: pages,
          onPage: (value) => load(nextPage: value),
        ),
      if (!loading && total > 0 && pages > 1)
        Text(
          '$total mục · Trang $page/$pages',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );
  Widget list(
    Widget header,
    Widget Function(LearningRecord) card, {
    required String empty,
    required String explanation,
  }) {
    final content = ListView.builder(
      key: PageStorageKey(path),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pageInsets(context),
      itemCount: 3,
      itemBuilder: (context, index) => index == 0
          ? header
          : index == 2
          ? status(empty: empty, explanation: explanation)
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AdaptiveCardGrid(
                children: [for (final item in items) card(item)],
              ),
            ),
    );
    return isDesktopLayout(context)
        ? content
        : RefreshIndicator(onRefresh: () => load(force: true), child: content);
  }
}

class SignCollectionsScreen extends StatefulWidget {
  const SignCollectionsScreen({super.key, this.saveEntryId});
  final String? saveEntryId;
  @override
  State<SignCollectionsScreen> createState() => _SignCollectionsScreenState();
}

class _SignCollectionsScreenState
    extends _CollectionPageState<SignCollectionsScreen> {
  @override
  String get path => '/sign-collections';
  bool get picking => widget.saveEntryId != null;
  Future<void> choose(LearningRecord row) =>
      perform('choose-${row['_id']}', () async {
        if (picking) {
          await service.addCollectionEntries('${row['_id']}', [
            widget.saveEntryId!,
          ]);
          if (!mounted) return;
          if (Navigator.canPop(context)) {
            Navigator.pop(context, true);
          } else {
            replaceAppRoute(context, '/collections/${row['_id']}');
          }
        } else {
          await pushAppRoute(context, '/collections/${row['_id']}');
          if (mounted) await load();
        }
      });
  Future<void> create() async {
    if (action != null) return;
    final row = await editSignCollection(context);
    if (!mounted || row == null) return;
    if (picking) {
      await choose(row);
    } else {
      await pushAppRoute(context, '/collections/${row['_id']}');
      if (mounted) await load(force: true);
    }
  }

  Future<void> enterCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _ShareCodeDialog(),
    );
    if (!mounted || code == null) return;
    await pushAppRoute(
      context,
      code == '/collections/discover' ? code : '/collections/shared/$code',
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: picking ? 'Thêm vào bộ' : 'Bộ sưu tập',
    showBack: picking,
    tabIndex: picking ? null : 1,
    scroll: false,
    padding: EdgeInsets.zero,
    actions: [
      IconButton(
        tooltip: 'Làm mới',
        onPressed: loading ? null : () => load(force: true),
        icon: const Icon(Icons.refresh),
      ),
    ],
    child: list(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!picking) ...[
            const LearningTabs(selected: 2),
            const SizedBox(height: 24),
          ],
          Heading(
            picking ? 'Chọn bộ để lưu ký hiệu' : 'Bộ sưu tập ký hiệu',
            size: 24,
          ),
          const SizedBox(height: 8),
          BodyText(
            picking
                ? 'Chọn một bộ có sẵn hoặc tạo bộ mới.'
                : 'Gom ký hiệu theo tình huống và ôn theo cách của bạn.',
          ),
          const SizedBox(height: 20),
          searchField('Tìm bộ sưu tập'),
          const SizedBox(height: 12),
          if (isDesktopLayout(context))
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CollectionAction(
                  'Tạo bộ sưu tập',
                  inline: true,
                  icon: Icons.add,
                  onPressed: action == null ? create : null,
                ),
                if (!picking) ...[
                  CollectionAction(
                    'Khám phá bộ công khai',
                    inline: true,
                    outlined: true,
                    icon: Icons.public_outlined,
                    onPressed: action == null
                        ? () => pushAppRoute(context, '/collections/discover')
                        : null,
                  ),
                  TextButton.icon(
                    onPressed: action == null ? enterCode : null,
                    icon: const Icon(Icons.link),
                    label: const Text('Tôi có mã hoặc liên kết'),
                  ),
                ],
              ],
            )
          else ...[
            CollectionAction(
              'Tạo bộ sưu tập',
              icon: Icons.add,
              onPressed: action == null ? create : null,
            ),
            if (!picking) ...[
              const SizedBox(height: 12),
              CollectionAction(
                'Khám phá bộ công khai',
                outlined: true,
                onPressed: action == null
                    ? () => pushAppRoute(context, '/collections/discover')
                    : null,
                icon: Icons.public_outlined,
              ),
              const SizedBox(height: 12),
              CollectionAction(
                'Tôi có mã hoặc liên kết',
                outlined: true,
                onPressed: action == null ? enterCode : null,
                icon: Icons.link,
              ),
            ],
          ],
          const SizedBox(height: 16),
        ],
      ),
      (row) => AppCard(
        onTap: action == null ? () => choose(row) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: SignPhoto(
                  collectionAvatarSource(row),
                  width: 64,
                  height: 72,
                  word: '${row['name']}',
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Heading('${row['name']}', size: 18),
                    const SizedBox(height: 6),
                    if ((row['wordCount'] as num? ?? 0) == 0 && !picking)
                      TextButton.icon(
                        onPressed: () => pushAppRoute(
                          context,
                          '/collections/${row['_id']}/add',
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Thêm ký hiệu đầu tiên'),
                      )
                    else
                      Text(
                        '${row['wordCount'] ?? 0} ký hiệu · ${row['reviewCount'] ?? 0} cần ôn',
                      ),
                    if ((row['personalWordCount'] as num? ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Gồm ${row['personalWordCount']} từ riêng của bạn',
                        ),
                      ),
                    if (row['shared'] == true)
                      Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          row['discoverable'] == true
                              ? 'Công khai trong khám phá'
                              : 'Chia sẻ bằng liên kết',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              action == 'choose-${row['_id']}'
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
      empty: picking ? 'Bạn chưa có bộ sưu tập' : 'Bắt đầu với một bộ nhỏ',
      explanation: picking ? 'Tạo một bộ để lưu ký hiệu này.' : 'Ví dụ: “Đi khám bệnh” hoặc “Giao tiếp hằng ngày”. Bạn có thể chọn từ có sẵn trong từ điển.',
    ),
  );
}

class _ShareCodeDialog extends StatefulWidget {
  const _ShareCodeDialog();
  @override
  State<_ShareCodeDialog> createState() => _ShareCodeDialogState();
}

class _ShareCodeDialogState extends State<_ShareCodeDialog> {
  final text = TextEditingController(), form = GlobalKey<FormState>();
  String? pasteError;
  bool pasting = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void open() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, collectionShareCode(text.text));
    }
  }

  Future<void> paste() async {
    if (pasting) return;
    setState(() {
      pasting = true;
      pasteError = null;
    });
    try {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final copied = value?.text?.trim() ?? '';
      if (copied.isEmpty) {
        setState(
          () => pasteError = 'Chưa có mã hoặc liên kết trong bộ nhớ sao chép.',
        );
      } else if (copied.length > 4096) {
        setState(
          () => pasteError =
              'Nội dung quá dài. Hãy sao chép riêng liên kết của bộ.',
        );
      } else {
        text.text = copied;
        text.selection = TextSelection.collapsed(offset: copied.length);
        setState(() {});
        form.currentState!.validate();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => pasteError =
              'Không đọc được bộ nhớ sao chép. Nhấn giữ trong ô để dán.',
        );
      }
    } finally {
      if (mounted) setState(() => pasting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Nhận bộ sưu tập',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng hộp nhận bộ',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 400,
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BodyText(
                      'Dán liên kết hoặc mã bạn nhận để xem trước bộ của người khác.',
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: text,
                      enabled: !pasting,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      minLines: 2,
                      maxLines: 3,
                      maxLength: 4096,
                      decoration: const InputDecoration(
                        labelText: 'Liên kết hoặc mã chia sẻ',
                        hintText: 'Dán vào đây',
                        alignLabelWithHint: true,
                        counterText: '',
                        errorMaxLines: 3,
                      ),
                      onChanged: (_) => setState(() => pasteError = null),
                      onFieldSubmitted: (_) => open(),
                      validator: (value) =>
                          collectionShareCode(value ?? '') == null
                          ? 'Dùng liên kết bộ sưu tập hoặc mã chia sẻ gồm 32 ký tự.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CollectionAction(
                        pasting ? 'Đang dán…' : 'Dán từ bộ nhớ',
                        outlined: true,
                        onPressed: pasting ? null : paste,
                        icon: Icons.content_paste_outlined,
                      ),
                    ),
                    if (pasteError != null)
                      Text(
                        pasteError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: CollectionAction(
                'Xem trước bộ sưu tập',
                icon: Icons.preview_outlined,
                onPressed: text.text.trim().isEmpty || pasting ? null : open,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: CollectionAction(
                'Khám phá bộ công khai',
                outlined: true,
                onPressed: () =>
                    Navigator.pop(context, '/collections/discover'),
                icon: Icons.public_outlined,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SignCollectionScreen extends StatefulWidget {
  const SignCollectionScreen({super.key, required this.id});
  final String id;
  @override
  State<SignCollectionScreen> createState() => _SignCollectionScreenState();
}

class _SignCollectionScreenState
    extends _CollectionPageState<SignCollectionScreen> {
  @override
  String get path => '/sign-collections/${widget.id}';
  String? expanded;
  LearningRecord get collection =>
      LearningRecord.from(data?['collection'] as Map? ?? {});
  Future<void> add() async {
    if (action != null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Heading('Thêm từ vào bộ', size: 22),
            const SizedBox(height: 16),
            CollectionAction(
              'Chọn từ thư viện',
              icon: Icons.menu_book_outlined,
              onPressed: () => Navigator.pop(sheet, 'library'),
            ),
            const SizedBox(height: 12),
            CollectionAction(
              'Tạo từ riêng',
              outlined: true,
              icon: Icons.edit_outlined,
              onPressed: () => Navigator.pop(sheet, 'create'),
            ),
            const SizedBox(height: 12),
            CollectionAction(
              'Thêm từ riêng đã có',
              outlined: true,
              icon: Icons.inventory_2_outlined,
              onPressed: () => Navigator.pop(sheet, 'existing'),
            ),
            const SizedBox(height: 16),
            const BodyText(
              'Từ riêng chỉ bạn nhìn thấy. Các từ đã tạo trước đây vẫn nằm trong “Thêm từ riêng đã có”.',
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'create') {
      await editPersonalWord(context, service, collectionId: widget.id);
    } else {
      await pushAppRoute(
        context,
        '/collections/${widget.id}/${choice == 'existing' ? 'personal' : 'add'}',
      );
    }
    if (mounted) await load(force: true);
  }

  final fullWords = <String, LearningRecord>{};
  final openedWords = <String>{};
  Future<void> editPrivate(LearningRecord item) =>
      perform('edit-private', () async {
        final word = item['imageDeferred'] == true
            ? await service.collectionWord(widget.id, '${item['_id']}')
            : item;
        if (!mounted) return;
        if (await editPersonalWord(
              context,
              service,
              collectionId: widget.id,
              word: word,
            ) &&
            mounted) {
          fullWords.remove('${item['_id']}');
          await load(force: true);
        }
      });
  Future<void> expandWord(LearningRecord item, bool open) async {
    setState(() {
      final id = '${item['_id']}';
      if (open) {
        openedWords.add(id);
        expanded = id;
      } else {
        openedWords.remove(id);
        if (expanded == id) expanded = null;
      }
    });
    if (open &&
        item['imageDeferred'] == true &&
        !fullWords.containsKey('${item['_id']}')) {
      await perform('image-${item['_id']}', () async {
        final word = await service.collectionWord(widget.id, '${item['_id']}');
        if (mounted) {
          setState(() {
            if (fullWords.length >= 5) fullWords.remove(fullWords.keys.first);
            fullWords['${item['_id']}'] = {
              ...item,
              ...word,
              'thumbnailUrl': word['imageUrl'],
              'imageUrls': ['${word['imageUrl'] ?? ''}']
                  .where((s) => s.isNotEmpty)
                  .toList(),
            };
          });
        }
      });
    }
  }

  Future<void> quiz() => perform('quiz', () async {
    final quiz = await service.startCollectionQuiz(widget.id);
    if (!mounted) return;
    await pushAppRoute(context, '/learn/quiz/${quiz['_id']}');
    if (mounted) await load(force: true);
  });
  Future<bool> confirm(String title, String message) => common.confirm(
    context,
    title: title,
    message: message,
    destructive: true,
    confirmLabel: 'Xóa',
    cancelLabel: 'Giữ lại',
  );
  Future<void> requestReview() async {
    if (action != null) return;
    final submit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Gửi lại nội dung để kiểm tra?'),
        content: const Text(
          'Gửi tên, ảnh đại diện, mô tả và các từ thư viện hiện tại cho quản trị. Từ riêng, ghi chú và tiến độ không được gửi. Bộ vẫn giữ trạng thái hiện tại trong lúc chờ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Chỉnh sửa tiếp'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gửi kiểm tra'),
          ),
        ],
      ),
    );
    if (submit != true || !mounted) return;
    await perform('review', () async {
      await service.requestCollectionReview(widget.id);
      if (mounted) {
        toast(context, 'Đã gửi lại bộ để kiểm tra.');
        await load(force: true);
      }
    });
  }

  Future<void> menu(String value) async {
    if (action != null) return;
    if (value == 'edit') {
      final updated = await editSignCollection(context, collection: collection);
      if (updated != null && mounted) {
        setState(() => data!['collection'] = {...collection, ...updated});
      }
    }
    if (value == 'share') {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _CollectionShareDialog(
          id: widget.id,
          initial: collection,
          service: service,
        ),
      );
      if (mounted) await load(force: true);
    }
    if (value == 'delete' &&
        await confirm(
          'Xóa bộ sưu tập?',
          'Các từ trong từ điển, ghi chú và tiến độ vẫn được giữ. Từ riêng sẽ được giữ trong danh sách chưa xếp bộ để bạn thêm lại vào bộ khác.',
        )) {
      if (!mounted) return;
      await perform('delete', () async {
        await service.deleteCollection(widget.id);
        if (mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          } else {
            replaceAppRoute(context, '/learn?tab=2');
          }
        }
      });
    }
  }

  Future<void> note(LearningRecord item) async {
    final value = await editSignNote(
      context,
      '${item['_id']}',
      initial: '${item['personalNote'] ?? ''}',
    );
    if (value == null || !mounted) return;
    setState(() {
      for (final row in data!['items'] as List) {
        if (row['_id'] == item['_id']) row['personalNote'] = value;
      }
    });
  }

  Future<void> remove(LearningRecord item) async {
    final personal = item['isPersonal'] == true;
    if (!await confirm(
      personal ? 'Xóa từ riêng?' : 'Bỏ ký hiệu khỏi bộ?',
      personal
          ? 'Từ riêng và ảnh của từ sẽ bị xóa khỏi tài khoản. Thao tác này không thể hoàn tác.'
          : 'Bạn vẫn tìm được ký hiệu này trong từ điển.',
    )) {
      return;
    }
    await perform('remove', () async {
      if (personal) {
        await service.deleteCollectionWord(widget.id, '${item['_id']}');
        fullWords.remove('${item['_id']}');
      } else {
        await service.removeCollectionEntry(widget.id, '${item['_id']}');
      }
      if (mounted) await load(force: true);
    });
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: '${collection['name'] ?? 'Bộ sưu tập'}',
    contentMaxWidth: 1120,
    scroll: false,
    padding: EdgeInsets.zero,
    actions: [
      IconButton(
        tooltip: 'Làm mới bộ',
        onPressed: loading || action != null ? null : () => load(force: true),
        icon: const Icon(Icons.refresh),
      ),
      if (data != null)
        PopupMenuButton<String>(
          tooltip: 'Quản lý bộ',
          onSelected: menu,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Chỉnh sửa bộ')),
            PopupMenuItem(value: 'share', child: Text('Chia sẻ bộ')),
            PopupMenuItem(value: 'delete', child: Text('Xóa bộ')),
          ],
        ),
    ],
    child: list(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SignPhoto(
                      collectionAvatarSource(collection),
                      width: 88,
                      height: 88,
                      word: 'Ảnh đại diện bộ',
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Heading(
                            '${collection['name'] ?? 'Bộ sưu tập'}',
                            size: 24,
                          ),
                          const SizedBox(height: 8),
                          if ('${collection['description'] ?? ''}'.isNotEmpty)
                            BodyText('${collection['description']}'),
                          if (data != null)
                            Text(
                              '${data!['summary']?['total'] ?? total} ký hiệu · ${data!['summary']?['review'] ?? 0} cần ôn',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ActionGroup(
                  children: [
                    CollectionAction(
                      'Thêm từ',
                      icon: Icons.playlist_add,
                      onPressed: action == null ? add : null,
                    ),
                    if ((collection['libraryWordCount'] as num? ??
                            collection['wordCount'] as num? ??
                            0) >
                        0)
                      CollectionAction(
                        action == 'quiz' ? 'Đang mở lượt ôn…' : 'Ôn bộ này',
                        outlined: true,
                        icon: Icons.school_outlined,
                        busy: action == 'quiz',
                        onPressed: data == null || action != null ? null : quiz,
                      ),
                  ],
                ),
                if ((collection['personalWordCount'] as num? ?? 0) > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${collection['personalWordCount']} từ riêng · chỉ bạn nhìn thấy',
                  ),
                ],
                if (collection['moderationState'] != null &&
                    collection['moderationState'] != 'CLEAR') ...[
                  const SizedBox(height: 16),
                  Notice(
                    '${collection['moderationState'] == 'BLOCKED' ? 'Bộ đang bị chặn chia sẻ' : 'Bộ đang ẩn khỏi khám phá'}. ${collection['moderationReason'] ?? ''} Bạn vẫn giữ toàn bộ dữ liệu và có thể chỉnh sửa bộ.',
                  ),
                  const SizedBox(height: 12),
                  CollectionAction(
                    collection['reviewRequestedAt'] != null
                        ? 'Đã gửi · Chờ kiểm tra'
                        : 'Gửi lại để kiểm tra',
                    outlined: true,
                    icon: Icons.fact_check_outlined,
                    busy: action == 'review',
                    onPressed:
                        action != null ||
                            collection['reviewRequestedAt'] != null
                        ? null
                        : requestReview,
                  ),
                ],
              ],
            ),
          ),
          if (total > 0 || query.isNotEmpty) ...[
            const SizedBox(height: 20),
            searchField('Tìm ký hiệu trong bộ'),
          ],
          const SizedBox(height: 20),
        ],
      ),
      (item) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SignPhoto(
                  item['thumbnailUrl'] as String?,
                  width: 64,
                  height: 72,
                  word: '${item['word']}',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Heading('${item['word']}', size: 19),
                      const SizedBox(height: 4),
                      Text(
                        item['isPersonal'] == true
                            ? 'Từ riêng · chỉ bạn thấy'
                            : learningLabels['${item['stage']}'] ?? 'Đang học',
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Tùy chọn ký hiệu ${item['word']}',
                  onSelected: action != null
                      ? null
                      : (value) => value == 'remove'
                            ? remove(item)
                            : item['isPersonal'] == true
                            ? editPrivate(item)
                            : note(item),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'note',
                      child: Text(
                        item['isPersonal'] == true
                            ? 'Chỉnh sửa từ riêng'
                            : 'Ghi chú riêng',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(
                        item['isPersonal'] == true
                            ? 'Xóa từ riêng'
                            : 'Bỏ khỏi bộ',
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if ('${item['personalNote'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${item['personalNote']}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(height: 12),
            CollectionAction(
              item['isPersonal'] == true
                  ? 'Chỉnh sửa từ riêng'
                  : '${item['personalNote'] ?? ''}'.isEmpty
                  ? 'Thêm ghi chú'
                  : 'Sửa ghi chú',
              outlined: true,
              onPressed: action != null
                  ? null
                  : () => item['isPersonal'] == true
                        ? editPrivate(item)
                        : note(item),
              icon: Icons.edit_note,
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              key: PageStorageKey(
                'collection-${widget.id}-media-${item['_id']}',
              ),
              tilePadding: EdgeInsets.zero,
              title: const Text('Xem mẫu ký hiệu'),
              onExpansionChanged: (value) => expandWord(item, value),
              children: [
                if (action == 'image-${item['_id']}')
                  const LinearProgressIndicator(),
                if (openedWords.contains('${item['_id']}') &&
                    (item['imageDeferred'] != true ||
                        fullWords.containsKey('${item['_id']}')))
                  LearningWordContent(
                    fullWords['${item['_id']}'] ?? item,
                    quizControls: true,
                    pauseVideo: expanded != '${item['_id']}',
                  ),
                if (openedWords.contains('${item['_id']}') &&
                    item['imageDeferred'] == true &&
                    !fullWords.containsKey('${item['_id']}') &&
                    action != 'image-${item['_id']}')
                  CollectionAction(
                    'Tải ảnh riêng',
                    outlined: true,
                    icon: Icons.image_outlined,
                    onPressed: action == null
                        ? () => expandWord(item, true)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
      empty: query.isEmpty ? 'Bộ sưu tập đang trống' : 'Không tìm thấy ký hiệu',
      explanation: query.isEmpty
          ? 'Bấm Thêm từ để chọn ký hiệu thư viện hoặc tạo từ riêng có ảnh, video và ví dụ của bạn.'
          : 'Thử tên hoặc cách gọi khác.',
    ),
  );
}

class CollectionWordPickerScreen extends StatefulWidget {
  const CollectionWordPickerScreen({
    super.key,
    required this.id,
    this.personal = false,
  });
  final String id;
  final bool personal;
  @override
  State<CollectionWordPickerScreen> createState() =>
      _CollectionWordPickerScreenState();
}

class _CollectionWordPickerScreenState
    extends _CollectionPageState<CollectionWordPickerScreen> {
  @override
  String get path =>
      '/sign-collections/${widget.id}/${widget.personal ? 'personal-words/available' : 'candidates'}';
  final selected = <String>{};
  void returnToCollection() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, true);
    } else {
      replaceAppRoute(context, '/collections/${widget.id}');
    }
  }

  bool exitAllowed = false;
  Future<void> leave() async {
    if (action != null) return;
    if (selected.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Bỏ các từ đang chọn?'),
          content: const Text('Các từ này chưa được thêm vào bộ.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Chọn tiếp'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bỏ lựa chọn'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => exitAllowed = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) returnToCollection();
  }

  Future<void> save() => perform('save', () async {
    if (widget.personal) {
      await service.attachCollectionWords(widget.id, selected.toList());
    } else {
      await service.addCollectionEntries(widget.id, selected.toList());
    }
    if (mounted) {
      setState(() => exitAllowed = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) returnToCollection();
    }
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: action == null && (selected.isEmpty || exitAllowed),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) leave();
    },
    child: AppPage(
      title: widget.personal ? 'Từ riêng đã có' : 'Thêm ký hiệu',
      footerInBody: true,
      actions: [
        TextButton(
          onPressed: selected.isEmpty || action != null
              ? null
              : () => setState(selected.clear),
          child: const Text('Bỏ chọn'),
        ),
      ],
      scroll: false,
      padding: EdgeInsets.zero,
      footer: CollectionAction(
        action == 'save' ? 'Đang thêm…' : 'Thêm ${selected.length} ký hiệu',
        icon: Icons.playlist_add,
        busy: action == 'save',
        onPressed: selected.isEmpty || action != null ? null : save,
      ),
      child: list(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BodyText(
              widget.personal
                  ? 'Chọn từ riêng chưa xếp bộ, bao gồm những từ bạn đã tạo trước đây. Ảnh và nội dung được giữ nguyên.'
                  : 'Chọn từ từ thư viện. Ảnh và video được dùng chung, không cần tải lên lại.',
            ),
            const SizedBox(height: 16),
            searchField('Tìm ký hiệu'),
            const SizedBox(height: 16),
          ],
        ),
        (item) => CheckboxListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          secondary: ExcludeSemantics(
            child: SignPhoto(
              item['thumbnailUrl'] as String?,
              width: 52,
              height: 60,
            ),
          ),
          title: Text('${item['word']}'),
          subtitle: item['inCollection'] == true
              ? const Text('Đã có trong bộ')
              : null,
          value:
              item['inCollection'] == true ||
              selected.contains('${item['_id']}'),
          onChanged: item['inCollection'] == true || action != null
              ? null
              : (value) => setState(() {
                  if (value == true) {
                    if (selected.length >= 200) {
                      toast(context, 'Tối đa 200 từ mỗi lần chọn.');
                      return;
                    }
                    selected.add('${item['_id']}');
                  } else {
                    selected.remove('${item['_id']}');
                  }
                }),
        ),
        empty: widget.personal && query.isEmpty
            ? 'Chưa có từ riêng chưa xếp bộ'
            : 'Không tìm thấy ký hiệu',
        explanation: widget.personal && query.isEmpty
            ? 'Quay lại bộ và chọn Thêm từ → Tạo từ riêng.'
            : 'Thử tên ngắn hơn hoặc cách gọi khác.',
      ),
    ),
  );
}

class _CollectionShareDialog extends StatefulWidget {
  const _CollectionShareDialog({
    required this.id,
    required this.initial,
    required this.service,
  });
  final String id;
  final LearningRecord initial;
  final LearningService service;
  @override
  State<_CollectionShareDialog> createState() => _CollectionShareDialogState();
}

class _CollectionShareDialogState extends State<_CollectionShareDialog> {
  late String code = '${widget.initial['shareCode'] ?? ''}';
  late bool discoverable =
      (widget.initial['discoveryRequested'] ??
          widget.initial['discoverable']) ==
      true;
  bool busy = false;
  bool showQr = false;
  String? error;
  bool get blocked => widget.initial['moderationState'] == 'BLOCKED';
  bool get restricted =>
      const {'BLOCKED', 'HIDDEN'}.contains(widget.initial['moderationState']);
  bool get hasLibraryWords =>
      (widget.initial['libraryWordCount'] as num? ??
          widget.initial['wordCount'] as num? ??
          0) >
      0;
  String get link =>
      '${Uri.base.resolve(ApiConfig.baseUrl).origin}/#/collections/shared/$code';
  bool get canShare => hasLibraryWords && !blocked;
  Future<void> change(bool enabled) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.service.shareCollection(widget.id, enabled);
      if (mounted) {
        setState(() {
          code = '${value['shareCode'] ?? ''}';
          discoverable =
              (value['discoveryRequested'] ?? value['discoverable']) == true;
          if (code.isEmpty) showQr = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = collectionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copy(bool link) async {
    try {
      await Clipboard.setData(ClipboardData(text: link ? this.link : code));
      if (mounted) {
        toast(context, link ? 'Đã sao chép liên kết.' : 'Đã sao chép mã.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Không sao chép được. Bạn có thể chọn và sao chép mã bên dưới.',
        );
      }
    }
  }

  Future<void> send(BuildContext anchor) async {
    if (busy || code.isEmpty) return;
    final box = anchor.findRenderObject() as RenderBox?;
    final position = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'Cùng học bộ “${widget.initial['name'] ?? 'Ký hiệu'}” trên SignVoice:\n$link',
          title: 'Chia sẻ bộ sưu tập SignVoice',
          sharePositionOrigin: position,
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Chưa mở được trình chia sẻ. Dùng “Sao chép liên kết” rồi dán vào Zalo hoặc tin nhắn.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish(bool enabled) async {
    if (busy) return;
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Đăng bộ lên khám phá?'),
          content: const Text(
            'Mọi người sẽ tìm được tên, ảnh đại diện, mô tả và các từ thư viện trong bộ. Từ riêng, ghi chú và tiến độ không được chia sẻ. Bạn có thể gỡ bộ bất cứ lúc nào.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Để riêng tư'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Đăng công khai'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.service.publishCollection(widget.id, enabled);
      if (mounted) {
        setState(() {
          code = '${value['shareCode'] ?? ''}';
          discoverable =
              (value['discoveryRequested'] ?? value['discoverable']) == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = collectionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Chia sẻ bộ sưu tập'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BodyText(
              'Chia sẻ ảnh đại diện và các từ thư viện trong bộ. Từ riêng, ghi chú và tiến độ của bạn không được chia sẻ.',
            ),
            const SizedBox(height: 16),
            if (blocked) ...[
              const Notice(
                'Bộ đang bị chặn. Liên kết và QR không thể mở cho người khác. Hãy xem lý do ở trang bộ và gửi lại sau khi chỉnh sửa.',
              ),
              const SizedBox(height: 12),
            ],
            if (!hasLibraryWords) ...[
              const Notice(
                'Thêm ít nhất một từ thư viện để người khác có nội dung xem. Từ riêng vẫn chỉ thuộc tài khoản của bạn.',
              ),
              const SizedBox(height: 12),
            ],
            if (code.isNotEmpty) ...[
              Builder(
                builder: (anchor) => CollectionAction(
                  'Chia sẻ qua ứng dụng',
                  icon: Icons.share_outlined,
                  busy: busy,
                  onPressed: busy || !canShare ? null : () => send(anchor),
                ),
              ),
              const SizedBox(height: 12),
              CollectionAction(
                'Sao chép liên kết',
                outlined: true,
                icon: Icons.link,
                onPressed: busy || blocked ? null : () => copy(true),
              ),
              const SizedBox(height: 12),
              CollectionAction(
                showQr ? 'Ẩn mã QR' : 'Hiện mã QR',
                outlined: true,
                onPressed: busy || blocked
                    ? null
                    : () => setState(() => showQr = !showQr),
                icon: Icons.qr_code_2,
              ),
              if (showQr) ...[
                const SizedBox(height: 16),
                Center(
                  child: Semantics(
                    image: true,
                    label: 'Mã QR mở bộ sưu tập được chia sẻ',
                    child: SizedBox.square(
                      dimension: (MediaQuery.sizeOf(context).width - 88)
                          .clamp(80.0, 220.0)
                          .toDouble(),
                      child: QrImageView(
                        data: link,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.all(24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const BodyText('Dùng camera điện thoại khác quét mã để mở bộ.'),
              ],
              const SizedBox(height: 12),
              ExpansionTile(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: const Text('Mã chia sẻ'),
                children: [
                  SelectableText(code, semanticsLabel: 'Mã chia sẻ $code'),
                ],
              ),
              const SizedBox(height: 12),
              CollectionAction(
                'Sao chép mã',
                outlined: true,
                icon: Icons.content_copy,
                onPressed: busy || blocked ? null : () => copy(false),
              ),
              const SizedBox(height: 12),
              CollectionAction(
                busy ? 'Đang cập nhật…' : 'Tắt mã chia sẻ',
                outlined: true,
                danger: true,
                icon: Icons.link_off,
                onPressed: busy ? null : () => change(false),
              ),
            ] else
              CollectionAction(
                busy ? 'Đang bật…' : 'Bật chia sẻ',
                busy: busy,
                icon: Icons.share_outlined,
                onPressed: busy || !canShare ? null : () => change(true),
              ),
            const SizedBox(height: 16),
            const Divider(),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hiện trong khám phá công khai'),
              subtitle: const Text(
                'Để mọi người tìm bộ trong SignVoice. Tắt mục này vẫn giữ liên kết riêng.',
              ),
              value: discoverable,
              onChanged: busy || (!canShare || restricted) && !discoverable
                  ? null
                  : publish,
            ),
            if (error != null) Notice(error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

class PublicSignCollectionsScreen extends StatefulWidget {
  const PublicSignCollectionsScreen({super.key});
  @override
  State<PublicSignCollectionsScreen> createState() =>
      _PublicSignCollectionsScreenState();
}

class _PublicSignCollectionsScreenState
    extends _CollectionPageState<PublicSignCollectionsScreen> {
  @override
  String get path => '/shared-collections';
  Future<void> preview(LearningRecord row) async {
    await pushAppRoute(context, '/collections/shared/${row['shareCode']}');
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => PublicCatalogPage(
    title: 'Bộ sưu tập công khai',
    current: 'collections',
    scroll: false,
    child: list(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              const Heading('Bộ sưu tập công khai', size: 28),
              Tooltip(
                message: 'Làm mới bộ công khai',
                child: TextButton.icon(
                  onPressed: loading ? null : () => load(force: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Làm mới bộ công khai'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const BodyText(
            'Tìm bộ được mọi người chủ động chia sẻ. Xem trước và lưu một bản riêng để học theo cách của bạn.',
          ),
          const SizedBox(height: 20),
          searchField('Tìm bộ công khai'),
          const SizedBox(height: 20),
        ],
      ),
      (row) => AppCard(
        onTap: () => preview(row),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: SignPhoto(
                    collectionAvatarSource(row),
                    width: 64,
                    height: 72,
                    word: '${row['name']}',
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Heading('${row['name']}', size: 19),
                      const SizedBox(height: 6),
                      Text('${row['wordCount'] ?? 0} ký hiệu'),
                      if ('${row['description'] ?? ''}'.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${row['description']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        (row['wordCount'] as num? ?? 0) > 0
                            ? 'Xem trước bộ'
                            : 'Đang chờ cập nhật ký hiệu',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
      empty: query.isEmpty
          ? 'Chưa có bộ công khai'
          : 'Chưa tìm thấy bộ phù hợp',
      explanation: query.isEmpty
          ? 'Các bộ được cộng đồng chia sẻ sẽ xuất hiện tại đây. Bạn có thể khám phá từ điển công khai trong lúc chờ bộ mới.'
          : 'Thử tên ngắn hơn hoặc từ khóa khác.',
    ),
  );
}

class SharedSignCollectionScreen extends StatefulWidget {
  const SharedSignCollectionScreen({super.key, required this.code});
  final String code;
  @override
  State<SharedSignCollectionScreen> createState() =>
      _SharedSignCollectionScreenState();
}

class _SharedSignCollectionScreenState
    extends _CollectionPageState<SharedSignCollectionScreen> {
  String? expanded;
  @override
  String get path => '/shared-collections/${widget.code}';
  Future<void> report() async {
    if (action != null) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              AuthScreen(returnRoute: '/collections/shared/${widget.code}'),
        ),
      );
      return;
    }
    if (auth.user?.isGuest == true) {
      toast(context, 'Đăng nhập tài khoản chính thức để gửi báo cáo.');
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CollectionReportDialog(service: service, code: widget.code),
    );
    if (saved == true && mounted) {
      toast(context, 'Đã ghi nhận báo cáo. Nhân viên sẽ kiểm tra nội dung.');
    }
  }

  Future<void> save() => perform('import', () async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              AuthScreen(returnRoute: '/collections/shared/${widget.code}'),
        ),
      );
      return;
    }
    final value = await service.importCollection(widget.code);
    if (!mounted) return;
    replaceAppRoute(context, '/collections/${value['_id']}');
  });
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    Widget shell(Widget content) {
      final actions = <Widget>[
        if (data != null)
          IconButton(
            tooltip: 'Báo cáo bộ sưu tập',
            onPressed: action == null ? report : null,
            icon: const Icon(Icons.flag_outlined),
          ),
      ];
      if (!auth.isAuthenticated || auth.user?.isGuest == true) {
        return PublicCatalogPage(
          title: 'Bộ được chia sẻ',
          current: 'collections',
          scroll: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              replaceAppRoute(context, '/collections/discover'),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Bộ sưu tập công khai'),
                        ),
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
              Expanded(child: content),
            ],
          ),
        );
      }
      return AppPage(
        title: 'Bộ được chia sẻ',
        actions: actions,
        scroll: false,
        padding: EdgeInsets.zero,
        child: content,
      );
    }

    return shell(
      list(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (data != null) ...[
              if ('${data!['collection']['avatarImage'] ?? ''}'.isNotEmpty) ...[
                Center(
                  child: SignPhoto(
                    collectionAvatarSource(
                      LearningRecord.from(data!['collection'] as Map),
                    ),
                    width: 88,
                    height: 88,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Heading('${data!['collection']['name']}', size: 24),
              const SizedBox(height: 8),
              if ('${data!['collection']['description'] ?? ''}'.isNotEmpty)
                BodyText('${data!['collection']['description']}'),
              const SizedBox(height: 12),
              Text('$total ký hiệu công khai'),
              const SizedBox(height: 16),
              CollectionAction(
                action == 'import'
                    ? 'Đang lưu bộ…'
                    : auth.isAuthenticated
                    ? 'Lưu vào bộ sưu tập của tôi'
                    : 'Đăng nhập để lưu bộ',
                icon: Icons.bookmark_add_outlined,
                busy: action == 'import',
                onPressed: action == null && total > 0 ? save : null,
              ),
              const SizedBox(height: 8),
              const BodyText(
                'Bạn nhận một bản độc lập gồm các từ thư viện. Từ riêng, ghi chú và tiến độ của người chia sẻ không được sao chép.',
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
        (item) => AppCard(
          child: ExpansionTile(
            key: PageStorageKey('shared-${widget.code}-media-${item['_id']}'),
            initiallyExpanded: expanded == item['_id'],
            onExpansionChanged: (open) =>
                setState(() => expanded = open ? '${item['_id']}' : null),
            tilePadding: EdgeInsets.zero,
            title: Text('${item['word']}'),
            leading: ExcludeSemantics(
              child: SignPhoto(
                item['thumbnailUrl'] as String?,
                width: 48,
                height: 52,
              ),
            ),
            children: [
              if (expanded == item['_id'])
                LearningWordContent(item, quizControls: true),
            ],
          ),
        ),
        empty: 'Bộ chưa có từ khả dụng',
        explanation: 'Các từ có thể đã được gỡ khỏi thư viện.',
      ),
    );
  }
}

class _CollectionReportDialog extends StatefulWidget {
  const _CollectionReportDialog({required this.service, required this.code});
  final LearningService service;
  final String code;
  @override
  State<_CollectionReportDialog> createState() =>
      _CollectionReportDialogState();
}

class _CollectionReportDialogState extends State<_CollectionReportDialog> {
  final form = GlobalKey<FormState>(), details = TextEditingController();
  String? category, error;
  bool busy = false;
  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.reportSharedCollection(
        widget.code,
        category!,
        details.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = collectionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text('Báo cáo bộ sưu tập'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BodyText(
                'Chọn vấn đề bạn gặp. Báo cáo được gửi để kiểm tra, không tự động chặn bộ. Danh tính của bạn không hiện cho nhân viên.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Vấn đề cần báo cáo',
                ),
                items: reportCategoryLabels.entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          e.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) => setState(() => category = value),
                validator: (value) =>
                    value == null ? 'Chọn vấn đề cần kiểm tra.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: details,
                readOnly: busy,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Mô tả thêm'),
                validator: (value) =>
                    category == 'OTHER' && (value?.trim().length ?? 0) < 5
                    ? 'Mô tả vấn đề bằng ít nhất 5 ký tự.'
                    : null,
              ),
              if (error != null) Notice(error!),
              const SizedBox(height: 16),
              CollectionAction(
                'Gửi báo cáo',
                icon: Icons.flag_outlined,
                busy: busy,
                onPressed: busy ? null : submit,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
      ],
    ),
  );
}
