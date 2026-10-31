import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/ui.dart';
import '../../services/admin/admin_workspace_service.dart';

class AdminEditorLayout extends StatelessWidget {
  const AdminEditorLayout({
    super.key,
    required this.resource,
    required this.children,
    this.action,
  });
  final String resource;
  final List<Widget> children;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final sections = children.whereType<AdminSection>().toList();
      final split =
          const {'users', 'categories'}.contains(resource) &&
          size.maxWidth >= 860 &&
          MediaQuery.textScalerOf(context).scale(1) < 1.6;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (split) ...[
            ...children.where((item) => item is! AdminSection),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: sections.first),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: Column(children: sections.skip(1).toList()),
                ),
              ],
            ),
          ] else
            ...children,
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      );
    },
  );
}

/// A bounded picker shared by management filters and editor fields.
class AdminSelectField extends FormField<String> {
  AdminSelectField({
    super.key,
    required this.label,
    required String? value,
    required this.options,
    required this.onChanged,
    this.searchable = false,
    super.validator,
  }) : super(
         initialValue: value,
         enabled: onChanged != null && options.isNotEmpty,
         builder: (state) => (state as _AdminSelectFieldState).content(),
       );
  final String label;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;
  final bool searchable;
  @override
  FormFieldState<String> createState() => _AdminSelectFieldState();
}

class _AdminSelectFieldState extends FormFieldState<String> {
  AdminSelectField get control => widget as AdminSelectField;
  bool choosing = false, focused = false;
  @override
  void didUpdateWidget(covariant AdminSelectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }

  Future<void> open() async {
    if (!control.enabled || choosing) return;
    setState(() => choosing = true);
    FocusScope.of(context).unfocus();
    await Scrollable.ensureVisible(
      context,
      alignment: .25,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
    );
    if (!mounted) return;
    final field = context.findRenderObject() as RenderBox;
    final origin = field.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(field.size.width, screen.width - 24.0);
    final left = origin.dx.clamp(
      12.0,
      math.max(12.0, screen.width - width - 12),
    );
    final below = screen.height - origin.dy - field.size.height - 18;
    final above = origin.dy - 18;
    final down = below >= 160 || below >= above;
    final available = math.max(100.0, down ? below : above);
    final panel = _AdminChoiceDialog(
      label: control.label,
      options: Map.of(control.options),
      selected: value,
      searchable: control.searchable || control.options.length > 8,
      maxHeight: math.min(440.0, available),
    );
    final selected = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Đóng lựa chọn',
      barrierColor: Colors.transparent,
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
      pageBuilder: (_, animation, secondary) => Stack(
        children: [
          Positioned(
            left: left.toDouble(),
            top: down ? origin.dy + field.size.height + 6 : null,
            bottom: down ? null : screen.height - origin.dy + 6,
            width: width,
            child: panel,
          ),
        ],
      ),
      transitionBuilder: (_, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    if (!mounted) return;
    setState(() => choosing = false);
    if (selected != null &&
        control.enabled &&
        control.options.containsKey(selected)) {
      didChange(selected);
      control.onChanged?.call(selected);
    }
  }

  Widget content() {
    final display =
        control.options[value] ?? 'Chọn ${control.label.toLowerCase()}';
    return Semantics(
      button: true,
      enabled: control.enabled,
      label: control.label,
      value: display,
      onTap: control.enabled ? open : null,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          // An outlined field paints its floating label above its own bounds.
          // InkWell already bounds the ripple using its borderRadius.
          clipBehavior: Clip.none,
          child: InkWell(
            onTap: control.enabled ? open : null,
            onFocusChange: (value) => setState(() => focused = value),
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              isFocused: focused || choosing,
              decoration: InputDecoration(
                labelText: control.label,
                floatingLabelBehavior: FloatingLabelBehavior.always,
                enabled: control.enabled,
                errorText: errorText,
                errorMaxLines: 3,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      display,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: control.enabled
                            ? null
                            : Theme.of(context).disabledColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    choosing ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: control.enabled
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).disabledColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminChoiceDialog extends StatefulWidget {
  const _AdminChoiceDialog({
    required this.label,
    required this.options,
    required this.selected,
    required this.searchable,
    this.maxHeight = 440,
  });
  final String label;
  final Map<String, String> options;
  final String? selected;
  final bool searchable;
  final double maxHeight;
  @override
  State<_AdminChoiceDialog> createState() => _AdminChoiceDialogState();
}

class _AdminChoiceDialogState extends State<_AdminChoiceDialog> {
  final search = TextEditingController(), scroll = ScrollController();
  String query = '';
  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context),
        scheme = Theme.of(context).colorScheme;
    final available = math.max(
      100.0,
      media.size.height -
          media.viewInsets.vertical -
          media.padding.vertical -
          48,
    );
    final rows = widget.options.entries
        .where((e) => e.value.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Material(
      key: const ValueKey('admin-choice-menu'),
      elevation: 10,
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(widget.maxHeight, available),
        ),
        child: Scrollbar(
          controller: scroll,
          thumbVisibility: widget.searchable,
          child: CustomScrollView(
            controller: scroll,
            shrinkWrap: true,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Chọn ${widget.label.toLowerCase()}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Đóng lựa chọn',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.searchable)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Tìm trong danh sách',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Xóa từ khóa',
                                onPressed: () {
                                  search.clear();
                                  setState(() => query = '');
                                },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                      onChanged: (value) =>
                          setState(() => query = value.trim()),
                    ),
                  ),
                ),
              if (rows.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Không tìm thấy lựa chọn phù hợp.'),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index],
                        selected = row.key == widget.selected;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Semantics(
                        selected: selected,
                        child: Material(
                          color: selected
                              ? scheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, row.key),
                            borderRadius: BorderRadius.circular(12),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 52),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        row.value,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: selected
                                                  ? scheme.onPrimaryContainer
                                                  : scheme.onSurface,
                                              fontWeight: selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ExcludeSemantics(
                                      child: Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 22,
                                        color: selected
                                            ? scheme.onPrimaryContainer
                                            : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminSection extends StatelessWidget {
  const AdminSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.icon,
  });
  final String title;
  final String? description;
  final IconData? icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(description!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );
}

const adminPermissionGroups = {
  'Khu vực truy cập': ['admin:access', 'staff:access'],
  'Tài khoản và phiên đăng nhập': [
    'users:read',
    'users:write',
    'sessions:read',
    'sessions:write',
  ],
  'Role và phân quyền': ['roles:read', 'roles:write'],
  'Từ điển và xuất bản': [
    'dictionary:read',
    'dictionary:write',
    'content:publish',
  ],
  'Danh mục': ['categories:read', 'categories:write'],
  'Bộ sưu tập công khai': ['collections:read', 'collections:moderate'],
};

class AdminPermissionPicker extends StatelessWidget {
  const AdminPermissionPicker({
    super.key,
    required this.selected,
    required this.allowed,
    required this.onChanged,
  });
  final Set<String> selected, allowed;
  final ValueChanged<Set<String>>? onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Bộ quyền · ${selected.length} đã chọn',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Text(
        onChanged == null ? 'Mở từng nhóm để xem quyền được cấp.' : 'Mở từng nhóm để chọn quyền. Thay đổi chỉ có hiệu lực sau khi lưu.',
      ),
      const SizedBox(height: 16),
      for (final group in adminPermissionGroups.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
                  ? AnimationStyle.noAnimation
                  : null,
              key: PageStorageKey('admin-permissions-${group.key}'),
              initiallyExpanded: group.key == 'Khu vực truy cập',
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              title: Text(
                group.key,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${group.value.where(selected.contains).length}/${group.value.length} quyền đã chọn',
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              children: [
                if (group.value.any(allowed.contains))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onChanged == null
                          ? null
                          : () {
                              final eligible = group.value
                                      .where(allowed.contains)
                                      .toSet(),
                                  next = {...selected};
                              if (eligible.every(selected.contains)) {
                                next.removeAll(eligible);
                              } else {
                                next.addAll(eligible);
                              }
                              onChanged!(next);
                            },
                      child: Text(
                        group.value
                                .where(allowed.contains)
                                .every(selected.contains)
                            ? 'Bỏ chọn nhóm'
                            : 'Chọn nhóm',
                      ),
                    ),
                  ),
                for (final permission in group.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: CheckboxListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      title: Text(adminPermissionLabels[permission]!),
                      value: selected.contains(permission),
                      onChanged:
                          onChanged != null && allowed.contains(permission)
                          ? (value) {
                              final next = {...selected};
                              if (value == true) {
                                next.add(permission);
                              } else {
                                next.remove(permission);
                              }
                              onChanged!(next);
                            }
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
    ],
  );
}
