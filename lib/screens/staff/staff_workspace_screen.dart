import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../services/staff/staff_workspace_service.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../admin/admin_management_screens.dart';
import '../../widgets/ui.dart';

class StaffWorkspaceScreen extends StatefulWidget {
  const StaffWorkspaceScreen({super.key, required this.path});
  final String path;
  @override
  State<StaffWorkspaceScreen> createState() => _StaffWorkspaceScreenState();
}

class _StaffWorkspaceScreenState extends State<StaffWorkspaceScreen> {
  final _search = TextEditingController();
  AdminPageData? _page;
  AdminRecord? _detail;
  int _number = 1, _request = 0;
  bool _loading = true, _initialized = false;
  String? _error, _status;
  String get resource => widget.path.split('/')[2];
  String? get id =>
      widget.path.split('/').length > 3 ? widget.path.split('/').last : null;
  StaffWorkspaceService get service => context.read<StaffWorkspaceService>();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (resource == 'content' && args is Map && args['filter'] == 'pending') {
        _status = 'DRAFT';
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final state = AppScope.of(context),
        epoch = AppScope.of(context).accountEpoch;
    bool current() => mounted && request == _request && state.isCurrent(epoch);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!const ['content', 'users'].contains(resource)) {
        throw const FormatException('Unknown staff resource');
      }
      final result = id == null
          ? await service.page(
              resource,
              page: _number,
              search: _search.text.trim(),
              status: _status,
            )
          : await service.detail(resource, id!);
      if (!current()) return;
      setState(() {
        if (result is AdminPageData) {
          _page = result;
        } else {
          _detail = result as AdminRecord;
        }
      });
    } catch (error) {
      if (current()) setState(() => _error = adminError(error));
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _edit([AdminRecord? record]) async {
    final epoch = AppScope.of(context).accountEpoch;
    final staffService = service;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => Provider<AdminWorkspaceService>.value(
          value: staffService,
          child: AdminEditorScreen(resource: 'dictionary', record: record),
        ),
      ),
    );
    if (changed == true && mounted && AppScope.of(context).isCurrent(epoch)) {
      await _load();
    }
  }

  Future<void> _approve() async {
    if (_detail == null) return;
    final epoch = AppScope.of(context).accountEpoch;
    final approved = await confirm(
      context,
      title: 'Xuất bản nội dung?',
      message: 'Mục từ này sẽ xuất hiện trong từ điển công khai.',
    );
    if (!approved || !mounted || !AppScope.of(context).isCurrent(epoch)) return;
    setState(() => _loading = true);
    try {
      await service.moderate(id!);
      if (mounted && AppScope.of(context).isCurrent(epoch)) await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = adminError(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _reject() async {
    final epoch = AppScope.of(context).accountEpoch;
    final staffService = service;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _RejectDialog(
        submit: (reason) async {
          if (!mounted || !AppScope.of(context).isCurrent(epoch)) {
            throw StateError('Tài khoản đã thay đổi.');
          }
          await staffService.moderate(id!, reason: reason);
        },
      ),
    );
    if (changed == true && mounted && AppScope.of(context).isCurrent(epoch)) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canEdit =
        resource == 'content' &&
        auth.can('dictionary:write') &&
        (_detail == null ||
            auth.can('content:publish') ||
            (_detail!['status'] == 'DRAFT' &&
                recordId(_detail!['createdBy']) == auth.user?.id));
    return AppPage(
      title: resource == 'content' ? 'Quản lý nội dung' : 'Người dùng',
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Tải lại',
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/staff/content'),
                child: const Text('Nội dung'),
              ),
              if (auth.can('users:read'))
                TextButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/staff/users'),
                  child: const Text('Người dùng'),
                ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            Notice(_error!),
            TextButton(onPressed: _load, child: const Text('Thử lại')),
          ],
          if (id == null) ...[
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Tìm kiếm',
                suffixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) {
                _number = 1;
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (resource == 'content')
              Wrap(
                spacing: 8,
                children: [
                  for (final status in [null, 'DRAFT', 'PUBLISHED', 'ARCHIVED'])
                    ChoiceChip(
                      label: Text(statusLabels[status] ?? 'Tất cả'),
                      selected: status == _status,
                      onSelected: _loading
                          ? null
                          : (_) {
                              setState(() {
                                _status = status;
                                _number = 1;
                              });
                              _load();
                            },
                    ),
                  if (canEdit)
                    FilledButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm bản nháp'),
                    ),
                ],
              ),
            if (_page != null) ...[
              if (_page!.items.isEmpty && !_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Chưa có dữ liệu phù hợp.'),
                ),
              for (final item in _page!.items)
                Card(
                  child: ListTile(
                    title: Text(
                      '${item[resource == 'content' ? 'word' : 'displayName']}',
                    ),
                    subtitle: Text(
                      resource == 'content'
                          ? statusLabels[item['status']] ?? '${item['status']}'
                          : '${item['email'] ?? 'Tài khoản khách'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(
                      context,
                      '/staff/$resource/${item['_id']}',
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: !_loading && _number > 1
                        ? () {
                            _number--;
                            _load();
                          }
                        : null,
                    child: const Text('Trước'),
                  ),
                  Text(
                    'Trang $_number / ${_page!.pages < 1 ? 1 : _page!.pages}',
                  ),
                  TextButton(
                    onPressed: !_loading && _number < _page!.pages
                        ? () {
                            _number++;
                            _load();
                          }
                        : null,
                    child: const Text('Sau'),
                  ),
                ],
              ),
            ],
          ] else if (_detail != null) ...[
            const SizedBox(height: 20),
            for (final field
                in resource == 'content'
                    ? [
                        'word',
                        'definition',
                        'status',
                        'usageExample',
                        'notes',
                        'videoUrl',
                      ]
                    : ['displayName', 'email', 'role', 'status'])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SelectableText(
                  '${_fieldLabels[field]}: ${field == 'status' ? statusLabels[_detail![field]] ?? _detail![field] : _detail![field] ?? 'Chưa có'}',
                ),
              ),
            if (resource == 'content')
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (canEdit)
                    FilledButton(
                      onPressed: _loading ? null : () => _edit(_detail),
                      child: const Text('Chỉnh sửa'),
                    ),
                  if (auth.can('content:publish') &&
                      _detail!['status'] != 'PUBLISHED')
                    FilledButton(
                      onPressed: _loading ? null : _approve,
                      child: const Text('Xuất bản'),
                    ),
                  if (canEdit)
                    OutlinedButton(
                      onPressed: _loading ? null : _reject,
                      child: const Text('Từ chối / trả về bản nháp'),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

const _fieldLabels = {
  'word': 'Từ / cụm từ',
  'definition': 'Định nghĩa',
  'status': 'Trạng thái',
  'usageExample': 'Ví dụ sử dụng',
  'notes': 'Hướng dẫn',
  'videoUrl': 'Video ký hiệu',
  'displayName': 'Họ và tên',
  'email': 'Email',
  'role': 'Vai trò',
};

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.submit});
  final Future<void> Function(String) submit;
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final reason = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Lý do từ chối'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: reason,
            maxLength: 1000,
            maxLines: 3,
            enabled: !busy,
          ),
          if (error != null) Text(error!),
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (reason.text.trim().isEmpty) {
                    setState(() => error = 'Vui lòng nhập lý do.');
                    return;
                  }
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.submit(reason.text.trim());
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (failure) {
                    if (mounted) {
                      setState(() {
                        error = adminError(failure);
                        busy = false;
                      });
                    }
                  }
                },
          child: Text(busy ? 'Đang gửi...' : 'Xác nhận'),
        ),
      ],
    ),
  );
}
