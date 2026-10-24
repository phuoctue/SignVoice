import '../api/api_client.dart';
import '../admin/admin_workspace_service.dart';

class StaffWorkspaceService extends AdminWorkspaceService {
  StaffWorkspaceService({super.apiClient})
    : api = apiClient ?? ApiClient.instance;
  final ApiClient api;
  Future<AdminPageData> page(
    String resource, {
    int page = 1,
    String search = '',
    String? status,
  }) async {
    final data = (await api.get(
      '/staff/$resource',
      queryParameters: {
        'page': '$page',
        'limit': '20',
        if (search.isNotEmpty) 'search': search,
        'status': ?status,
      },
    ))['data'];
    final pagination = data['pagination'];
    return AdminPageData(
      (data[resource == 'content' ? 'items' : 'users'] as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      page,
      (pagination['pages'] as num).toInt(),
      (pagination['total'] as num).toInt(),
    );
  }

  Future<AdminRecord> detail(String resource, String id) async =>
      Map<String, dynamic>.from(
        (await api.get('/staff/$resource/$id'))['data'],
      );
  Future<void> moderate(String id, {String? reason}) async {
    await api.post(
      '/staff/content/$id/${reason == null ? 'approve' : 'reject'}',
      body: reason == null ? null : {'reason': reason},
    );
  }

  @override
  Future<void> save(String resource, AdminRecord body, {String? id}) async {
    if (id == null) {
      final draft = {...body}..remove('status');
      await api.post('/dictionary', body: draft);
    } else {
      await api.patch('/staff/content/$id', body: body);
    }
  }
}
