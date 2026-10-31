import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../../services/api/api_exception.dart';
import '../../widgets/ui.dart';
import 'admin_dashboard_screen.dart';
import 'admin_password_dialog.dart';
import 'admin_ui.dart';

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
    final auth = context.read<AuthProvider>(),
        account = context.read<AuthProvider>().accountEpoch;
    if (resource == 'users' && auth.can('roles:read')) {
      unawaited(_loadRoleLabels(epoch, account, auth));
    }
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
      if (mounted && epoch == _loadEpoch && auth.accountEpoch == account) {
        setState(() => _data = result);
      }
    } catch (error) {
      if (mounted && epoch == _loadEpoch) {
        setState(() => _error = adminError(error));
      }
    } finally {
      if (mounted && epoch == _loadEpoch) setState(() => _loading = false);
    }
  }

  Future<void> _loadRoleLabels(
    int epoch,
    int account,
    AuthProvider auth,
  ) async {
    try {
      final roles = await service.roles();
      if (mounted &&
          epoch == _loadEpoch &&
          auth.accountEpoch == account &&
          auth.can('roles:read')) {
        setState(() => _roles = roles);
      }
    } catch (_) {
      // Account rows render immediately; auxiliary role labels can arrive later.
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
    if (changed == true &&
        mounted &&
        context.read<AuthProvider>().accountEpoch == account) {
      _page = 1;
      await _load();
    }
  }

  Future<void> _resetPassword(AdminRecord record) async {
    final epoch = context.read<AuthProvider>().accountEpoch;
    final activeService = service;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminPasswordDialog(
        userId: recordId(record['_id']),
        name: '${record['email'] ?? record['displayName']}',
        service: activeService,
      ),
    );
    if (changed == true &&
        mounted &&
        context.read<AuthProvider>().accountEpoch == epoch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã đặt lại mật khẩu. Người dùng cần đăng nhập lại.'),
        ),
      );
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
    if (confirmed != true ||
        !mounted ||
        context.read<AuthProvider>().accountEpoch != account) {
      return;
    }
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
    final auth = context.watch<AuthProvider>(),
        canWrite = context.watch<AuthProvider>().can('$resource:write');
    final module = adminModules[resource]!;
    final wideRows =
        kIsWeb &&
        MediaQuery.sizeOf(context).width >= 1100 &&
        MediaQuery.textScalerOf(context).scale(1) < 1.6;
    final filters = resource == 'dictionary'
        ? ['DRAFT', 'PUBLISHED', 'ARCHIVED']
        : resource == 'users'
        ? ['ACTIVE', 'SUSPENDED', 'DELETED']
        : <String>[];
    return AppPage(
      title: widget.review ? 'Duyệt nội dung' : module.title,
      tabIndex: 4,
      scroll: false,
      padding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Làm mới',
          onPressed: _loading || _mutating ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          if (!_mutating) await _load();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              module.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Text(
                  _data == null && _loading
                      ? 'Đang tải…'
                      : '${_data?.total ?? 0} ${resource == 'sessions' ? 'phiên' : 'mục'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (canWrite && resource != 'sessions')
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _mutating ? null : () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm mới'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (resource == 'users' || resource == 'dictionary') ...[
              TextField(
                controller: _search,
                maxLength: 100,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: resource == 'users'
                      ? 'Tìm tên hoặc email'
                      : 'Tìm trong từ điển',
                  counterText: '',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Tìm kiếm',
                    onPressed: _mutating
                        ? null
                        : () {
                            _page = 1;
                            _load();
                          },
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
                onSubmitted: (_) {
                  if (!_mutating) {
                    _page = 1;
                    _load();
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
            if (filters.isNotEmpty) ...[
              AdminSelectField(
                label: 'Trạng thái',
                value: _status ?? '',
                options: {
                  '': 'Tất cả',
                  for (final value in filters) value: statusLabels[value]!,
                },
                onChanged: _mutating
                    ? null
                    : (value) {
                        setState(() => _status = value.isEmpty ? null : value);
                        _page = 1;
                        _load();
                      },
              ),
              const SizedBox(height: 20),
            ],
            if (_loading || _mutating)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null) ...[
              Notice(_error!),
              TextButton(onPressed: _load, child: const Text('Thử lại')),
              const SizedBox(height: 16),
            ],
            if (!_loading &&
                _error == null &&
                (_data?.items.isEmpty ?? false)) ...[
              EmptyView(
                title: _status != null || _search.text.trim().isNotEmpty
                    ? 'Không tìm thấy kết quả'
                    : 'Chưa có dữ liệu.',
                description: _status != null || _search.text.trim().isNotEmpty
                    ? 'Thử đổi từ khóa hoặc trạng thái đã chọn.'
                    : 'Các mục sẽ xuất hiện ở đây khi được tạo.',
                icon: module.icon,
              ),
              if (_status != null || _search.text.trim().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    _search.clear();
                    setState(() => _status = null);
                    _page = 1;
                    _load();
                  },
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Xóa bộ lọc'),
                ),
            ],
            if (wideRows && (_data?.items.isNotEmpty ?? false))
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 64, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tên / nội dung',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Thông tin & trạng thái',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            for (final record in _data?.items ?? <AdminRecord>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: wideRows
                        ? Row(
                            children: [
                              Expanded(child: Text(_title(record))),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _subtitle(record),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          )
                        : Text(_title(record)),
                    subtitle: wideRows
                        ? null
                        : Text(
                            _subtitle(record),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: resource == 'roles'
                        ? () => showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(_title(record)),
                              content: SizedBox(
                                width: 440,
                                child: SingleChildScrollView(
                                  child: AdminPermissionPicker(
                                    selected:
                                        (record['permissions'] as List? ?? [])
                                            .cast<String>()
                                            .toSet(),
                                    allowed: const {},
                                    onChanged: null,
                                  ),
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
                              } else if (value == 'password') {
                                _resetPassword(record);
                              } else {
                                _delete(record);
                              }
                            },
                            itemBuilder: (_) => [
                              if (resource == 'users' &&
                                  record['accountType'] == 'LOCAL' &&
                                  record['isGuest'] != true &&
                                  record['status'] != 'DELETED' &&
                                  recordId(record['_id']) != auth.user?.id)
                                const PopupMenuItem(
                                  value: 'password',
                                  child: Text('Đặt lại mật khẩu'),
                                ),
                              if (resource != 'sessions')
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Chỉnh sửa'),
                                ),
                              if (!(resource == 'users' &&
                                  recordId(record['_id']) == auth.user?.id))
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
              ),
            if ((_data?.pages ?? 0) > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Trang trước',
                      onPressed: _page > 1 && !_loading && !_mutating
                          ? () {
                              _page--;
                              _load();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Flexible(
                      child: Text(
                        '$_page / ${_data!.pages}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Trang sau',
                      onPressed: _page < _data!.pages && !_loading && !_mutating
                          ? () {
                              _page++;
                              _load();
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
  bool _showPassword = false;
  late int _accountEpoch;
  late String? _accountId;
  bool get _sameAccount =>
      mounted &&
      context.read<AuthProvider>().accountEpoch == _accountEpoch &&
      context.read<AuthProvider>().user?.id == _accountId;
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
      key: ValueKey('admin-field-$key'),
      controller: _fields[key],
      enabled: !_saving,
      obscureText: password && !_showPassword,
      minLines: lines > 1 ? 2 : 1,
      maxLines: lines,
      maxLength: max,
      keyboardType: email
          ? TextInputType.emailAddress
          : url
          ? TextInputType.url
          : key == 'sortOrder'
          ? TextInputType.number
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      textInputAction: lines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        alignLabelWithHint: lines > 1,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixIcon: password
            ? IconButton(
                tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                onPressed: _saving
                    ? null
                    : () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
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
    child: AdminSelectField(
      value: value,
      label: label,
      options: {
        for (final option in options) option: statusLabels[option] ?? option,
      },
      onChanged: _saving || !enabled
          ? null
          : (value) => setState(() => change(value)),
    ),
  );
  Widget optionDropdown(
    String label,
    String value,
    ValueChanged<String> change, {
    bool enabled = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: AdminSelectField(
      value: _options.any((item) => recordId(item['_id']) == value)
          ? value
          : null,
      label: label,
      searchable: resource == 'dictionary',
      options: {
        for (final option in _options)
          recordId(option['_id']): '${option['name']}',
      },
      onChanged: _saving || !enabled
          ? null
          : (value) => setState(() => change(value)),
      validator: (value) =>
          value == null || value.isEmpty ? 'Vui lòng chọn $label.' : null,
    ),
  );
  Future<void> _save() async {
    if (_saving || !_sameAccount || !_optionsReady) {
      return;
    }
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && invalid.first.mounted) {
        await Scrollable.ensureVisible(
          invalid.first.context,
          alignment: .2,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        );
      }
      return;
    }
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
    final canSave =
        !_saving &&
        _optionsReady &&
        _sameAccount &&
        auth.can('$resource:write');
    final inlineAction =
        isDesktopLayout(context) &&
        const {'users', 'categories'}.contains(resource);
    final submit = AppButton(
      editing ? 'Lưu thay đổi' : 'Tạo mới',
      icon: Icons.save_outlined,
      busy: _saving,
      onPressed: canSave ? _save : null,
    );
    return PopScope(
      canPop: !_saving,
      child: AppPage(
        title:
            '${editing ? 'Chỉnh sửa' : 'Thêm'} ${adminModules[resource]!.title.toLowerCase()}',
        showBack: !_saving,
        contentMaxWidth: 1040,
        footerInBody: true,
        footer: inlineAction
            ? null
            : AppButton(
                'Lưu thay đổi',
                icon: Icons.save_outlined,
                busy: _saving,
                onPressed: canSave ? _save : null,
              ),
        child: Form(
          key: _form,
          child: AdminEditorLayout(
            resource: resource,
            action: inlineAction
                ? Wrap(
                    spacing: 12,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Hủy'),
                      ),
                      SizedBox(width: 260, child: submit),
                    ],
                  )
                : null,
            children: [
              if (_loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
              ],
              if (_error != null) ...[
                Notice(_error!),
                const SizedBox(height: 12),
                if (!_optionsReady)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _loadOptions,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Tải lại lựa chọn'),
                    ),
                  ),
              ],
              if (resource == 'roles') ...[
                AdminSection(
                  title: 'Thông tin vai trò',
                  icon: Icons.admin_panel_settings_outlined,
                  children: [
                    field('name', 'Tên role', min: 2, max: 50),
                    field(
                      'key',
                      'Mã role',
                      min: 2,
                      max: 40,
                      hint: 'VD: CONTENT_EDITOR',
                    ),
                    field('description', 'Mô tả', lines: 3),
                  ],
                ),
                AdminPermissionPicker(
                  selected: _permissions,
                  allowed: adminPermissionLabels.keys.where(auth.can).toSet(),
                  onChanged: _saving
                      ? null
                      : (next) => setState(() => _permissions = next),
                ),
              ],
              if (resource == 'users') ...[
                AdminSection(
                  title: 'Thông tin tài khoản',
                  icon: Icons.person_outline,
                  children: [
                    field('displayName', 'Tên hiển thị', min: 2, max: 50),
                    if (record['isGuest'] != true)
                      field('email', 'Email', min: 1, max: 254, email: true),
                  ],
                ),
                if (!editing)
                  AdminSection(
                    title: 'Mật khẩu',
                    icon: Icons.lock_outline,
                    description: 'Dùng 8–128 ký tự, gồm chữ cái và số.',
                    children: [
                      field(
                        'password',
                        'Mật khẩu ban đầu',
                        min: 8,
                        max: 128,
                        password: true,
                      ),
                    ],
                  ),
                AdminSection(
                  title: 'Vai trò và trạng thái',
                  icon: Icons.manage_accounts_outlined,
                  children: [
                    optionDropdown(
                      'Role',
                      _role,
                      (value) => _role = value,
                      enabled:
                          _optionsReady &&
                          !ownAccount &&
                          record['isGuest'] != true,
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
                ),
              ],
              if (resource == 'dictionary') ...[
                AdminSection(
                  title: 'Nội dung ký hiệu',
                  icon: Icons.menu_book_outlined,
                  children: [
                    field('word', 'Từ / cụm từ', min: 1, max: 200),
                    field(
                      'definition',
                      'Định nghĩa',
                      min: 5,
                      max: 2000,
                      lines: 4,
                    ),
                  ],
                ),
                AdminSection(
                  title: 'Ảnh và video',
                  icon: Icons.perm_media_outlined,
                  children: [
                    field(
                      'videoUrl',
                      'URL video ký hiệu',
                      min: 1,
                      max: 2000,
                      url: true,
                    ),
                    field(
                      'thumbnailUrl',
                      'URL ảnh minh họa',
                      max: 2000,
                      url: true,
                      hint: 'Không bắt buộc',
                    ),
                  ],
                ),
                AdminSection(
                  title: 'Phân loại và hiển thị',
                  icon: Icons.category_outlined,
                  children: [
                    if (_optionsReady && _options.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Hãy tạo danh mục đang hoạt động trước khi thêm mục từ.',
                        ),
                      ),
                    optionDropdown(
                      'Danh mục',
                      _category,
                      (value) => _category = value,
                      enabled: _optionsReady,
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
                    const Text(
                      'Bản nháp chưa xuất hiện trong từ điển công khai.',
                    ),
                  ],
                ),
                AdminSection(
                  title: 'Thông tin bổ sung',
                  icon: Icons.notes_outlined,
                  children: [
                    field(
                      'tags',
                      'Từ khóa',
                      max: 1000,
                      hint: 'Cách nhau bằng dấu phẩy',
                    ),
                    field('usageExample', 'Ví dụ sử dụng', max: 1000, lines: 3),
                  ],
                ),
              ],
              if (resource == 'categories') ...[
                AdminSection(
                  title: 'Thông tin danh mục',
                  icon: Icons.folder_outlined,
                  children: [
                    field('name', 'Tên danh mục', min: 2, max: 50),
                    field(
                      'slug',
                      'Slug',
                      min: 1,
                      max: 80,
                      hint: 'VD: giao-tiep',
                    ),
                    field('description', 'Mô tả', lines: 3),
                  ],
                ),
                AdminSection(
                  title: 'Sắp xếp và hiển thị',
                  icon: Icons.sort,
                  children: [
                    field('sortOrder', 'Thứ tự hiển thị', min: 1, max: 5),
                    dropdown('Trạng thái', _status, [
                      'ACTIVE',
                      'ARCHIVED',
                    ], (value) => _status = value),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
