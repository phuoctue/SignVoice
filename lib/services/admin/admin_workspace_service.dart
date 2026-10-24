import '../api/api_client.dart';
import '../api/api_exception.dart';

typedef AdminRecord = Map<String, dynamic>;

class AdminPageData {
  const AdminPageData(this.items, this.page, this.pages, this.total);
  final List<AdminRecord> items;
  final int page, pages, total;
}

class AdminWorkspaceService {
  AdminWorkspaceService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient.instance;
  final ApiClient _api;

  Future<AdminRecord> stats() async =>
      Map<String, dynamic>.from((await _api.get('/admin/stats'))['data']);

  Future<AdminPageData> list(
    String resource, {
    int page = 1,
    String search = '',
    String? status,
    String? role,
  }) async {
    final response = await _api.get(
      '/admin/$resource',
      queryParameters: {
        'page': '$page',
        'limit': '20',
        if (search.isNotEmpty) 'search': search,
        'status': ?status,
        'role': ?role,
      },
    );
    final data = response['data'];
    if (data is List) {
      return AdminPageData(
        data.map((item) => Map<String, dynamic>.from(item)).toList(),
        1,
        1,
        data.length,
      );
    }
    final items =
        data[resource == 'users'
                ? 'users'
                : resource == 'sessions'
                ? 'sessions'
                : 'items']
            as List;
    final pagination = data['pagination'];
    return AdminPageData(
      items.map((item) => Map<String, dynamic>.from(item)).toList(),
      (pagination['page'] as num).toInt(),
      (pagination['pages'] as num).toInt(),
      (pagination['total'] as num).toInt(),
    );
  }

  Future<List<AdminRecord>> roles() async => (await list('roles')).items;
  Future<List<AdminRecord>> categories() async =>
      (await list('categories')).items;
  Future<List<AdminRecord>> roleOptions() async =>
      ((await _api.get('/admin/users/role-options'))['data'] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
  Future<List<AdminRecord>> activeCategories() async =>
      ((await _api.get('/categories'))['data'] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
  Future<AdminPageData> published({
    int page = 1,
    String search = '',
    String? categoryId,
    String sort = 'word_asc',
  }) async {
    final response = await _api.get(
      '/dictionary',
      queryParameters: {
        'limit': '20',
        'skip': '${(page - 1) * 20}',
        if (search.isNotEmpty) 'search': search,
        'categoryId': ?categoryId,
        'sort': sort,
      },
    );
    final total = (response['pagination']['total'] as num).toInt();
    return AdminPageData(
      (response['data'] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      page,
      (total / 20).ceil(),
      total,
    );
  }

  Future<AdminPageData> favoriteEntries(Set<String> ids) async {
    final items = await Future.wait(
      ids.where((id) => RegExp(r'^[a-f0-9]{24}$').hasMatch(id)).map((id) async {
        try {
          return Map<String, dynamic>.from(
            (await _api.get('/dictionary/$id', requiresAuth: false))['data'],
          );
        } on NotFoundException {
          return null;
        }
      }),
    );
    final entries = items.whereType<AdminRecord>().toList();
    return AdminPageData(entries, 1, 1, entries.length);
  }

  Future<AdminRecord> publishedEntry(String id) async =>
      Map<String, dynamic>.from(
        (await _api.get('/dictionary/$id', requiresAuth: false))['data'],
      );

  Future<void> save(String resource, AdminRecord body, {String? id}) async {
    if (id == null) {
      await _api.post('/admin/$resource', body: body);
    } else {
      await _api.patch('/admin/$resource/$id', body: body);
    }
  }

  Future<void> delete(String resource, String id) async {
    await _api.delete('/admin/$resource/$id');
  }
}

const adminPermissionLabels = {
  'admin:access': 'Truy cập tab Quản trị',
  'staff:access': 'Truy cập khu vực nhân viên',
  'users:read': 'Xem tài khoản',
  'users:write': 'Thêm, sửa, xóa tài khoản và gán role',
  'roles:read': 'Xem role',
  'roles:write': 'Thêm, sửa, xóa role',
  'dictionary:read': 'Xem toàn bộ từ điển',
  'dictionary:write': 'Thêm, sửa, xóa mục từ điển',
  'content:publish': 'Xuất bản và quản lý nội dung công khai',
  'categories:read': 'Xem danh mục',
  'categories:write': 'Thêm, sửa, xóa danh mục',
  'sessions:read': 'Xem phiên đăng nhập',
  'sessions:write': 'Thu hồi phiên đăng nhập',
};
