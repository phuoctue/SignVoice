import '../../core/navigation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../widgets/web_workspace.dart';

import 'package:provider/provider.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import '../../services/user/avatar_picker.dart';
import 'learning_widgets.dart' show SignPhoto;

const reportCategoryLabels = {
  'INAPPROPRIATE': 'Nội dung không phù hợp',
  'MISLEADING': 'Nội dung sai hoặc gây hiểu nhầm',
  'SPAM': 'Quảng cáo, spam',
  'COPYRIGHT': 'Vi phạm bản quyền',
  'OTHER': 'Vấn đề khác',
};

/// Collection actions use one shape and a full, bounded hit area in every state.
class CollectionAction extends StatelessWidget {
  const CollectionAction(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.busy = false,
    this.danger = false,
    this.inline = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined, busy, danger, inline;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.primary;
    final style = OutlinedButton.styleFrom(
      minimumSize: Size(inline ? 0 : double.infinity, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      foregroundColor: outlined
          ? color
          : danger
          ? scheme.onError
          : scheme.onPrimary,
      backgroundColor: outlined ? Colors.transparent : color,
      disabledForegroundColor: scheme.onSurface.withValues(alpha: .38),
      disabledBackgroundColor: outlined
          ? Colors.transparent
          : scheme.onSurface.withValues(alpha: .12),
      side: outlined
          ? BorderSide(color: danger ? scheme.error : scheme.outline)
          : BorderSide.none,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy) ...[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          ExcludeSemantics(child: Icon(icon, size: 20)),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    final button = outlined
        ? OutlinedButton(
            onPressed: busy ? null : onPressed,
            style: style,
            clipBehavior: Clip.antiAlias,
            child: content,
          )
        : FilledButton(
            onPressed: busy ? null : onPressed,
            style: style,
            clipBehavior: Clip.antiAlias,
            child: content,
          );
    if (!inline && isDesktopLayout(context)) {
      return Align(
        heightFactor: 1,
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: SizedBox(width: double.infinity, child: button),
        ),
      );
    }
    return button;
  }
}

String collectionError(Object error) =>
    error is ApiException ? error.message : 'Chưa thực hiện được. Hãy thử lại.';
String? collectionAvatarSource(LearningRecord row) =>
    '${row['avatarImage'] ?? ''}'.isNotEmpty
    ? row['avatarImage'] as String
    : row['thumbnailUrl'] as String?;

class LearningTabs extends StatelessWidget {
  const LearningTabs({super.key, required this.selected});
  final int selected;
  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopLayout(context);
    final labels = [
      'Khám phá',
      'Đang học',
      'Bộ sưu tập',
      if (desktop) ...['Tiến độ', 'Lịch sử học tập'],
    ];
    final paths = [
      '/dictionary',
      '/learn?tab=1',
      '/learn?tab=2',
      '/learn/insights',
      '/learn/history',
    ];
    final icons = [
      Icons.explore_outlined,
      Icons.school_outlined,
      Icons.collections_bookmark_outlined,
      Icons.insights_outlined,
      Icons.history_edu_outlined,
    ];
    Widget tab(int i) {
      final scheme = Theme.of(context).colorScheme;
      final active = i == selected;
      return Semantics(
        selected: active,
        button: true,
        child: Tooltip(
          message: labels[i],
          child: Material(
            color: active
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: active ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              focusColor: scheme.primary.withAlpha(50),
              hoverColor: scheme.primary.withAlpha(20),
              onTap: () {
                if (!active) {
                  if (kIsWeb || WebWorkspaceScope.contains(context)) {
                    openRoot(context, paths[i]);
                  } else {
                    replaceAppRoute(context, '/learn?tab=$i');
                  }
                }
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 16 : 8,
                  vertical: 12,
                ),
                child: desktop
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icons[i], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Icon(icons[i], size: 24),
                          const SizedBox(height: 8),
                          Text(labels[i], textAlign: TextAlign.center),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
    }

    if (desktop) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (var i = 0; i < labels.length; i++) tab(i)],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
              child: tab(i),
            ),
          ),
      ],
    );
  }
}

Future<LearningRecord?> editSignCollection(
  BuildContext context, {
  LearningRecord? collection,
  Future<AvatarSelection?> Function()? avatarPicker,
}) => showDialog<LearningRecord>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CollectionEditor(
    service: context.read<LearningService>(),
    collection: collection,
    avatarPicker: avatarPicker,
  ),
);

class _CollectionEditor extends StatefulWidget {
  const _CollectionEditor({
    required this.service,
    this.collection,
    this.avatarPicker,
  });
  final Future<AvatarSelection?> Function()? avatarPicker;
  final LearningService service;
  final LearningRecord? collection;
  @override
  State<_CollectionEditor> createState() => _CollectionEditorState();
}

class _CollectionEditorState extends State<_CollectionEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.collection?['name'] as String? ?? '',
  );
  late final description = TextEditingController(
    text: widget.collection?['description'] as String? ?? '',
  );
  bool busy = false;
  bool picking = false;
  late String avatar = '${widget.collection?['avatarImage'] ?? ''}';
  String? error;
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || picking || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = widget.collection == null
          ? await widget.service.createCollection(
              name.text.trim(),
              description.text.trim(),
              avatarImage: avatar,
            )
          : await widget.service.updateCollection(
              '${widget.collection!['_id']}',
              name.text.trim(),
              description.text.trim(),
              avatarImage: avatar,
            );
      if (mounted) Navigator.pop(context, value);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = collectionError(e);
          busy = false;
        });
      }
    }
  }

  Future<void> pick() async {
    if (busy || picking) return;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final image =
          await (widget.avatarPicker ??
              () => pickAvatarImage(maxDimension: 128, maxBytes: 72 * 1024))();
      if (mounted && image != null) setState(() => avatar = image.dataUrl);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : 'Chưa chọn được ảnh. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !picking,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        widget.collection == null ? 'Tạo bộ sưu tập' : 'Chỉnh sửa bộ',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: SignPhoto(
                    avatar,
                    word: 'Ảnh đại diện bộ',
                    width: 88,
                    height: 88,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CollectionAction(
                avatar.isEmpty ? 'Thêm ảnh đại diện' : 'Đổi ảnh đại diện',
                outlined: true,
                icon: Icons.add_photo_alternate_outlined,
                busy: picking,
                onPressed: busy ? null : pick,
              ),
              if (avatar.isNotEmpty) ...[
                const SizedBox(height: 12),
                CollectionAction(
                  'Bỏ ảnh đại diện',
                  outlined: true,
                  icon: Icons.close,
                  onPressed: busy || picking
                      ? null
                      : () => setState(() => avatar = ''),
                ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: name,
                autofocus: false,
                readOnly: busy,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Tên bộ',
                  hintText: 'Ví dụ: Giao tiếp khi đi khám',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nhập tên bộ sưu tập.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: description,
                readOnly: busy,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Mô tả (không bắt buộc)',
                ),
              ),
              if (error != null) Notice(error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy || picking ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy || picking ? null : save,
          child: Text(busy ? 'Đang lưu…' : 'Lưu bộ'),
        ),
      ],
    ),
  );
}

Future<String?> editSignNote(
  BuildContext context,
  String entryId, {
  String? initial,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SignNoteEditor(
    service: context.read<LearningService>(),
    entryId: entryId,
    initial: initial,
  ),
);

class _SignNoteEditor extends StatefulWidget {
  const _SignNoteEditor({
    required this.service,
    required this.entryId,
    this.initial,
  });
  final LearningService service;
  final String entryId;
  final String? initial;
  @override
  State<_SignNoteEditor> createState() => _SignNoteEditorState();
}

class _SignNoteEditorState extends State<_SignNoteEditor> {
  final text = TextEditingController();
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      text.text = widget.initial!;
      loading = false;
    } else {
      load();
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final row = await widget.service.signNote(widget.entryId);
      if (mounted) {
        setState(() {
          text.text = '${row['text'] ?? ''}';
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = collectionError(e));
    }
  }

  Future<void> save() async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.saveSignNote(widget.entryId, text.text.trim());
      if (mounted) Navigator.pop(context, text.text.trim());
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = collectionError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('Ghi chú của bạn'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BodyText(
              'Chỉ bạn nhìn thấy ghi chú này, kể cả khi chia sẻ bộ.',
            ),
            const SizedBox(height: 16),
            if (loading && error == null) const LinearProgressIndicator(),
            TextField(
              controller: text,
              readOnly: loading || busy,
              maxLength: 2000,
              minLines: 3,
              maxLines: 7,
              decoration: const InputDecoration(
                labelText: 'Cách nhớ, ngữ cảnh hoặc từ hay nhầm',
              ),
            ),
            if (error != null) ...[
              Notice(error!),
              if (loading)
                TextButton(
                  onPressed: load,
                  child: const Text('Tải lại ghi chú'),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy || loading ? null : save,
          child: Text(busy ? 'Đang lưu…' : 'Lưu ghi chú'),
        ),
      ],
    ),
  );
}

String? collectionShareCode(String input) {
  final value = input.trim();
  if (RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) return value;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  final fragment = uri.fragment;
  final location = fragment.startsWith('/') ? Uri.tryParse(fragment) : uri;
  final parts = location?.pathSegments ?? [];
  return parts.length == 3 &&
          parts[0] == 'collections' &&
          parts[1] == 'shared' &&
          RegExp(r'^[a-f0-9]{32}$').hasMatch(parts[2])
      ? parts[2]
      : null;
}
