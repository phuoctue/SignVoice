import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../../services/api/api_exception.dart';
import '../../widgets/ui.dart';
import 'admin_dashboard_screen.dart';

String adminError(Object error) => error is ApiException
    ? error.message
    : 'Không thể kết nối máy chủ. Hãy thử lại.';
String recordId(dynamic value) =>
    value is Map ? '${value['_id']}' : '${value ?? ''}';
const statusLabels = {
  'ACTIVE': 'Hoạt động',
  'SUSPENDED': 'Đã khóa',
  'DELETED': 'Đã xóa',
  'DRAFT': 'Bản nháp',
  'PUBLISHED': 'Đã xuất bản',
  'ARCHIVED': 'Lưu trữ',
  'BEGINNER': 'Cơ bản',
  'INTERMEDIATE': 'Trung bình',
  'ADVANCED': 'Nâng cao',
};

class AdminResourceScreen extends StatefulWidget {
  const AdminResourceScreen({
    super.key,
    required this.resource,
    this.review = false,
  });
  final String resource;
  final bool review;
  @override
  State<AdminResourceScreen> createState() => _AdminResourceScreenState();
}

class _AdminResourceScreenState extends State<AdminResourceScreen> {
  final _search = TextEditingController();
  AdminPageData? _data;
  List<AdminRecord> _roles = [];
  String? _error, _status;
  bool _loading = true, _mutating = false;
  int _page = 1;
  int _loadEpoch = 0;
  String get resource => widget.resource;
  AdminWorkspaceService get service => context.read<AdminWorkspaceService>();
  @override
  void initState() {
    super.initState();
    _status = widget.review ? 'DRAFT' : null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await service.list(
        resource,
        page: _page,
        search: _search.text.trim(),
        status: _status,
      );
      if (mounted &&
          epoch == _loadEpoch &&
          resource == 'users' &&
          context.read<AuthProvider>().can('roles:read')) {
        try {
          final roles = await service.roles();
          if (mounted && epoch == _loadEpoch) _roles = roles;
        } catch (_) {
          /* User list still works. */
        }
      }
      if (mounted && epoch == _loadEpoch) setState(() => _data = result);
    } catch (error) {
      if (mounted && epoch == _loadEpoch) {
        setState(() => _error = adminError(error));
      }
    } finally {
      if (mounted && epoch == _loadEpoch) setState(() => _loading = false);
    }
  }

  Future<void> _edit([AdminRecord? record]) async {
    final account = context.read<AuthProvider>().accountEpoch;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminEditorScreen(resource: resource, record: record),
      ),
    );
    if (changed == true && mounted && context.read<AuthProvider>().accountEpoch == account) {
      _page = 1;
      await _load();
    }
  }

  Future<void> _delete(AdminRecord record) async {
    final account = context.read<AuthProvider>().accountEpoch;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          resource == 'sessions' ? 'Thu hồi phiên?' : 'Xóa ${_title(record)}?',
        ),
        content: Text(
          resource == 'users'
              ? 'Tài khoản sẽ bị vô hiệu hóa và các phiên đăng nhập bị thu hồi.'
              : resource == 'sessions'
              ? 'Thiết bị sẽ phải đăng nhập lại.'
              : 'Thao tác này sẽ xóa dữ liệu đã chọn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(resource == 'sessions' ? 'Thu hồi' : 'Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || context.read<AuthProvider>().accountEpoch != account) return;
    setState(() => _mutating = true);
    try {
      await service.delete(resource, recordId(record['_id']));
      if (mounted) {
        _page = 1;
        await _load();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(adminError(error))));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  String _title(AdminRecord record) => switch (resource) {
    'users' => '${record['displayName']}',
    'dictionary' => '${record['word']}',
    'sessions' =>
      record['userId'] is Map
          ? '${record['userId']['displayName']}'
          : 'Phiên đăng nhập',
    _ => '${record['name']}',
  };
  String _roleLabel(AdminRecord record) {
    final id = recordId(record['customRoleId']);
    for (final role in _roles) {
      if (recordId(role['_id']) == id) return '${role['name']}';
    }
    return id.isNotEmpty ? 'Role tùy chỉnh' : '${record['role']}';
  }

  String _subtitle(AdminRecord record) => switch (resource) {
    'users' =>
      '${record['email'] ?? 'Tài khoản dùng thử'}\n${_roleLabel(record)} · ${statusLabels[record['status']] ?? record['status']}',
    'roles' =>
      '${record['key']} · ${(record['permissions'] as List? ?? []).length} quyền${record['system'] == true ? ' · Hệ thống' : ''}\n${record['description'] ?? ''}',
    'dictionary' =>
      '${record['categoryId'] is Map ? record['categoryId']['name'] : 'Danh mục'} · ${statusLabels[record['status']] ?? record['status']}\n${record['definition']}',
    'categories' =>
      '${record['slug']} · ${statusLabels[record['status']] ?? record['status']}\n${record['wordCount'] ?? 0} mục đã xuất bản',
    'sessions' =>
      '${record['userId'] is Map ? record['userId']['email'] ?? '' : ''}\n${record['sessionType']} · ${record['deviceInfo'] ?? 'Thiết bị'}',
    _ => '',
  };
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canWrite = auth.can('$resource:write');
    final module = adminModules[resource]!;
    final filters = resource == 'dictionary'
        ? ['DRAFT', 'PUBLISHED', 'ARCHIVED']
        : resource == 'users'
        ? ['ACTIVE', 'SUSPENDED', 'DELETED']
        : <String>[];
    return AppPage(
      title: widget.review ? 'Duyệt nội dung' : module.title,
      tabIndex: 4,
      scroll: false,
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: _loading || _mutating ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_data?.total ?? 0} ${resource == 'sessions' ? 'phiên' : 'mục'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (canWrite && resource != 'sessions')
                FilledButton.icon(
                  onPressed: _mutating ? null : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm mới'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (resource == 'users' || resource == 'dictionary') ...[
            TextField(
              controller: _search,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: 'Tìm kiếm',
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: 'Tìm kiếm',
                  onPressed: () {
                    _page = 1;
                    _load();
                  },
                  icon: const Icon(Icons.search),
                ),
              ),
              onSubmitted: (_) {
                _page = 1;
                _load();
              },
            ),
            const SizedBox(height: 10),
          ],
          if (filters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<String>(
                initialValue: _status ?? '',
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Tất cả')),
                  for (final value in filters)
                    DropdownMenuItem(
                      value: value,
                      child: Text(statusLabels[value]!),
                    ),
                ],
                onChanged: (value) {
                  _status = value == '' ? null : value;
                  _page = 1;
                  _load();
                },
              ),
            ),
          if (_loading || _mutating) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Thử lại')),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (!_loading &&
                      _error == null &&
                      (_data?.items.isEmpty ?? false))
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('Chưa có dữ liệu.')),
                    ),
                  if (_error == null)
                    for (final record in _data?.items ?? <AdminRecord>[])
                      Card(
                        child: ListTile(
                          title: Text(_title(record)),
                          subtitle: Text(
                            _subtitle(record),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: resource == 'roles'
                              ? () => showDialog<void>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(_title(record)),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final permission
                                              in record['permissions']
                                                      as List? ??
                                                  [])
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Text(
                                                '• ${adminPermissionLabels[permission] ?? permission}',
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Đóng'),
                                      ),
                                    ],
                                  ),
                                )
                              : null,
                          trailing:
                              canWrite &&
                                  record['system'] != true &&
                                  !(resource == 'dictionary' &&
                                      record['status'] == 'PUBLISHED' &&
                                      !auth.can('content:publish'))
                              ? PopupMenuButton<String>(
                                  enabled: !_mutating,
                                  tooltip: 'Thao tác',
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _edit(record);
                                    } else {
                                      _delete(record);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (resource != 'sessions')
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Chỉnh sửa'),
                                      ),
                                    if (!(resource == 'users' &&
                                        recordId(record['_id']) ==
                                            auth.user?.id))
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          resource == 'sessions'
                                              ? 'Thu hồi phiên'
                                              : 'Xóa',
                                        ),
                                      ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                ],
              ),
            ),
          ),
          if ((_data?.pages ?? 0) > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Trang trước',
                  onPressed: _page > 1 && !_loading
                      ? () {
                          _page--;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_page / ${_data!.pages}'),
                IconButton(
                  tooltip: 'Trang sau',
                  onPressed: _page < _data!.pages && !_loading
                      ? () {
                          _page++;
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

class AdminEditorScreen extends StatefulWidget {
  const AdminEditorScreen({super.key, required this.resource, this.record});
  final String resource;
  final AdminRecord? record;
  @override
  State<AdminEditorScreen> createState() => _AdminEditorScreenState();
}

class _AdminEditorScreenState extends State<AdminEditorScreen> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _fields = {};
  List<AdminRecord> _options = [];
  late Set<String> _permissions;
  late String _status, _difficulty, _role, _category;
  bool _loading = false, _saving = false, _optionsReady = false;
  late int _accountEpoch;
  late String? _accountId;
  bool get _sameAccount => mounted && context.read<AuthProvider>().accountEpoch == _accountEpoch && context.read<AuthProvider>().user?.id == _accountId;
  String? _error;
  AdminRecord get record => widget.record ?? {};
  bool get editing => widget.record != null;
  String get resource => widget.resource;
  bool get ownAccount =>
      resource == 'users' &&
      recordId(record['_id']) == context.read<AuthProvider>().user?.id;
  @override
  void initState() {
    super.initState();
    _accountEpoch = context.read<AuthProvider>().accountEpoch;
    _accountId = context.read<AuthProvider>().user?.id;
    _optionsReady = !['users', 'dictionary'].contains(resource);
    for (final key in [
      'name',
      'key',
      'description',
      'email',
      'displayName',
      'password',
      'word',
      'definition',
      'videoUrl',
      'thumbnailUrl',
      'usageExample',
      'slug',
      'sortOrder',
    ]) {
      _fields[key] = TextEditingController(
        text: '${record[key] ?? (key == 'sortOrder' ? 0 : '')}',
      );
    }
    _fields['tags'] = TextEditingController(
      text: (record['tags'] as List? ?? []).join(', '),
    );
    _permissions = Set<String>.from(record['permissions'] as List? ?? []);
    _status =
        '${record['status'] ?? (resource == 'dictionary' ? 'DRAFT' : 'ACTIVE')}';
    _difficulty = '${record['difficulty'] ?? 'BEGINNER'}';
    _role = recordId(record['customRoleId']).isNotEmpty
        ? recordId(record['customRoleId'])
        : '${record['role'] ?? 'USER'}';
    _category = recordId(record['categoryId']);
    if (resource == 'users' || resource == 'dictionary') {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadOptions();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _optionsReady = false;
      _error = null;
    });
    try {
      final service = context.read<AdminWorkspaceService>();
      final options = resource == 'users'
          ? await service.roleOptions()
          : await service.activeCategories();
      if (_sameAccount) {
        setState(() {
          _optionsReady = true;
          _options = options;
          final id = resource == 'users' ? _role : _category;
          if (id.isNotEmpty &&
              !options.any((option) => recordId(option['_id']) == id)) {
            _options.add({
              '_id': id,
              'name': resource == 'users'
                  ? 'Role hiện tại'
                  : (record['categoryId'] is Map
                        ? record['categoryId']['name']
                        : 'Danh mục hiện tại'),
            });
          }
          if (_category.isEmpty &&
              resource == 'dictionary' &&
              options.isNotEmpty) {
            _category = recordId(options.first['_id']);
          }
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = adminError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String text(String key) => _fields[key]!.text.trim();
  Widget field(
    String key,
    String label, {
    int min = 0,
    int max = 500,
    int lines = 1,
    bool email = false,
    bool url = false,
    bool password = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_saving,
      obscureText: password,
      maxLines: lines,
      maxLength: max,
      keyboardType: email
          ? TextInputType.emailAddress
          : url
          ? TextInputType.url
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
      ),
      validator: (value) {
        final input = (value ?? '').trim();
        if (input.length < min) return 'Cần ít nhất $min ký tự.';
        if (input.length > max) return 'Tối đa $max ký tự.';
        if (email && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input)) {
          return 'Email không hợp lệ.';
        }
        if (url &&
            input.isNotEmpty &&
            (!['https', 'http'].contains(Uri.tryParse(input)?.scheme) ||
                (Uri.tryParse(input)?.host.isEmpty ?? true))) {
          return 'Nhập URL http hoặc https hợp lệ.';
        }
        if (password &&
            (!RegExp('[a-zA-Z]').hasMatch(input) ||
                !RegExp('[0-9]').hasMatch(input))) {
          return 'Mật khẩu cần có chữ và số.';
        }
        if (key == 'key' &&
            (!RegExp(r'^[A-Z][A-Z0-9_]{1,39}$').hasMatch(input.toUpperCase()) ||
                ['USER', 'STAFF', 'ADMIN'].contains(input.toUpperCase()))) {
          return 'Mã role gồm chữ, số, dấu _; không dùng USER/STAFF/ADMIN.';
        }
        if (key == 'slug' && !RegExp(r'^[a-z0-9-]+$').hasMatch(input)) {
          return 'Dùng chữ thường, số và dấu -.';
        }
        if (key == 'sortOrder' &&
            ((int.tryParse(input) ?? -1) < 0 ||
                (int.tryParse(input) ?? 10001) > 10000)) {
          return 'Nhập số nguyên từ 0 đến 10000.';
        }
        return null;
      },
    ),
  );
  Widget dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> change, {
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(statusLabels[option] ?? option),
          ),
      ],
      onChanged: _saving || !enabled
          ? null
          : (value) => setState(() => change(value!)),
    ),
  );
  Widget optionDropdown(
    String label,
    String value,
    ValueChanged<String> change, {
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      initialValue: _options.any((item) => recordId(item['_id']) == value)
          ? value
          : null,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: [
        for (final option in _options)
          DropdownMenuItem(
            value: recordId(option['_id']),
            child: Text('${option['name']}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _saving || !enabled
          ? null
          : (value) => setState(() => change(value!)),
      validator: (value) =>
          value == null || value.isEmpty ? 'Vui lòng chọn $label.' : null,
    ),
  );
  Future<void> _save() async {
    if (!_sameAccount || !_optionsReady || !_form.currentState!.validate()) return;
    final AdminRecord body;
    switch (resource) {
      case 'roles':
        body = {
          'name': text('name'),
          'key': text('key').toUpperCase(),
          'description': text('description'),
          'permissions': _permissions.toList(),
        };
      case 'users':
        body = {
          if (record['isGuest'] != true) 'email': text('email').toLowerCase(),
          'displayName': text('displayName'),
          if (!editing) 'password': _fields['password']!.text,
          if (editing && !ownAccount) 'status': _status,
        };
        final oldRole = recordId(record['customRoleId']).isNotEmpty
            ? recordId(record['customRoleId'])
            : '${record['role']}';
        if (!ownAccount && (!editing || _role != oldRole)) {
          if (['USER', 'STAFF', 'ADMIN'].contains(_role)) {
            body['role'] = _role;
          } else {
            body['customRoleId'] = _role;
          }
        }
      case 'dictionary':
        body = {
          'word': text('word'),
          'definition': text('definition'),
          'videoUrl': text('videoUrl'),
          'thumbnailUrl': text('thumbnailUrl'),
          'categoryId': _category,
          'difficulty': _difficulty,
          'status': _status,
          'tags': text('tags')
              .split(',')
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toList(),
          'usageExample': text('usageExample'),
        };
      case 'categories':
        body = {
          'name': text('name'),
          'slug': text('slug'),
          'description': text('description'),
          'sortOrder': int.parse(text('sortOrder')),
          'status': _status,
        };
      default:
        return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AdminWorkspaceService>().save(
        resource,
        body,
        id: editing ? recordId(record['_id']) : null,
      );
      if (!_sameAccount) return;
      if (resource == 'roles' &&
          mounted &&
          context.read<AuthProvider>().user?.customRoleId ==
              recordId(record['_id'])) {
        await context.read<AuthProvider>().refreshUser();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = adminError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return PopScope(
      canPop: !_saving,
      child: AppPage(
        title:
            '${editing ? 'Chỉnh sửa' : 'Thêm'} ${adminModules[resource]!.title.toLowerCase()}',
        showBack: !_saving,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
                if (_options.isEmpty &&
                    (resource == 'users' || resource == 'dictionary'))
                  TextButton(
                    onPressed: _loadOptions,
                    child: const Text('Tải lại lựa chọn'),
                  ),
              ],
              if (!_loading) ...[
                if (resource == 'roles') ...[
                  field('name', 'Tên role', min: 2, max: 50),
                  field(
                    'key',
                    'Mã role',
                    min: 2,
                    max: 40,
                    hint: 'VD: CONTENT_EDITOR',
                  ),
                  field('description', 'Mô tả', lines: 3),
                  Text(
                    'Bộ quyền',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final permission in adminPermissionLabels.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(permission.value),
                      value: _permissions.contains(permission.key),
                      onChanged: !_saving && auth.can(permission.key)
                          ? (selected) => setState(() {
                              if (selected!) {
                                _permissions.add(permission.key);
                              } else {
                                _permissions.remove(permission.key);
                              }
                            })
                          : null,
                    ),
                ],
                if (resource == 'users') ...[
                  field('displayName', 'Tên hiển thị', min: 2, max: 50),
                  if (record['isGuest'] != true)
                    field('email', 'Email', min: 1, max: 254, email: true),
                  if (!editing)
                    field(
                      'password',
                      'Mật khẩu ban đầu',
                      min: 8,
                      max: 128,
                      password: true,
                    ),
                  optionDropdown(
                    'Role',
                    _role,
                    (value) => _role = value,
                    enabled: !ownAccount && record['isGuest'] != true,
                  ),
                  if (editing)
                    dropdown(
                      'Trạng thái',
                      _status,
                      ['ACTIVE', 'SUSPENDED', 'DELETED'],
                      (value) => _status = value,
                      enabled: !ownAccount,
                    ),
                  if (ownAccount)
                    const Text(
                      'Tài khoản đang dùng giữ nguyên role và trạng thái.',
                    ),
                ],
                if (resource == 'dictionary') ...[
                  if (_options.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text(
                        'Hãy tạo danh mục đang hoạt động trước khi thêm mục từ.',
                      ),
                    ),
                  field('word', 'Từ / cụm từ', min: 1, max: 200),
                  field(
                    'definition',
                    'Định nghĩa',
                    min: 5,
                    max: 2000,
                    lines: 4,
                  ),
                  field(
                    'videoUrl',
                    'URL video ký hiệu',
                    min: 1,
                    max: 2000,
                    url: true,
                  ),
                  field(
                    'thumbnailUrl',
                    'URL ảnh minh họa (tùy chọn)',
                    max: 2000,
                    url: true,
                  ),
                  optionDropdown(
                    'Danh mục',
                    _category,
                    (value) => _category = value,
                  ),
                  dropdown('Độ khó', _difficulty, [
                    'BEGINNER',
                    'INTERMEDIATE',
                    'ADVANCED',
                  ], (value) => _difficulty = value),
                  dropdown('Trạng thái', _status, [
                    'DRAFT',
                    if (auth.can('content:publish')) 'PUBLISHED',
                    'ARCHIVED',
                  ], (value) => _status = value),
                  field('tags', 'Từ khóa (cách nhau bằng dấu phẩy)', max: 1000),
                  field('usageExample', 'Ví dụ sử dụng', max: 1000, lines: 3),
                ],
                if (resource == 'categories') ...[
                  field('name', 'Tên danh mục', min: 2, max: 50),
                  field('slug', 'Slug', min: 1, max: 80, hint: 'VD: giao-tiep'),
                  field('description', 'Mô tả', lines: 3),
                  field('sortOrder', 'Thứ tự hiển thị', min: 1, max: 5),
                  dropdown('Trạng thái', _status, [
                    'ACTIVE',
                    'ARCHIVED',
                  ], (value) => _status = value),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving || !_optionsReady || !_sameAccount || !auth.can('$resource:write')
                      ? null
                      : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Đang lưu...' : 'Lưu thay đổi'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
