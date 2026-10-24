import '../../models/user_model.dart';
import '../../models/staff_stats_model.dart';
import '../../models/dictionary_entry_model.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Service for staff operations
class StaffService {
  static StaffService? _instance;
  final ApiClient _apiClient;

  StaffService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient.instance;

  static StaffService get instance {
    _instance ??= StaffService();
    return _instance!;
  }

  /// Get content with pagination and filters
  Future<Map<String, dynamic>> getContent({
    int page = 1,
    int limit = 20,
    String? status,
    String? category,
    String? search,
    String? sortBy,
    String? order,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'status': ?status,
        'category': ?category,
        if (search != null && search.isNotEmpty) 'search': search,
        'sortBy': ?sortBy,
        'order': ?order,
      };

      final response = await _apiClient.get(
        '/staff/content',
        queryParameters: queryParams,
      );

      if (response['success'] == true && response['data'] != null) {
        final List<dynamic> items = response['data']['items'] ?? [];
        final entries = items
            .map((json) => DictionaryEntryModel.fromJson(json))
            .toList();

        return {
          'entries': entries,
          'pagination': response['data']['pagination'] ?? {},
        };
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Get content by ID
  Future<DictionaryEntryModel> getContentById(String id) async {
    try {
      final response = await _apiClient.get('/staff/content/$id');

      if (response['success'] == true && response['data'] != null) {
        return DictionaryEntryModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Update content
  Future<DictionaryEntryModel> updateContent(
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _apiClient.patch('/staff/content/$id', body: data);

      if (response['success'] == true && response['data'] != null) {
        return DictionaryEntryModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Failed to update content');
    } catch (e) {
      rethrow;
    }
  }

  /// Approve content
  Future<DictionaryEntryModel> approveContent(String id) async {
    try {
      final response = await _apiClient.post('/staff/content/$id/approve');

      if (response['success'] == true && response['data'] != null) {
        return DictionaryEntryModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Failed to approve content');
    } catch (e) {
      rethrow;
    }
  }

  /// Reject content
  Future<DictionaryEntryModel> rejectContent(String id, String reason) async {
    try {
      final response = await _apiClient.post(
        '/staff/content/$id/reject',
        body: {'reason': reason},
      );

      if (response['success'] == true && response['data'] != null) {
        return DictionaryEntryModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Failed to reject content');
    } catch (e) {
      rethrow;
    }
  }

  /// Get users with pagination and filters
  Future<Map<String, dynamic>> getUsers({
    int page = 1,
    int limit = 20,
    String? search,
    String? role,
    String? status,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (search != null && search.isNotEmpty) 'search': search,
        'role': ?role,
        'status': ?status,
      };

      final response = await _apiClient.get(
        '/staff/users',
        queryParameters: queryParams,
      );

      if (response['success'] == true && response['data'] != null) {
        final List<dynamic> items = response['data']['users'] ?? [];
        final users = items.map((json) => UserModel.fromJson(json)).toList();

        return {
          'users': users,
          'pagination': response['data']['pagination'] ?? {},
        };
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Get user by ID
  Future<UserModel> getUserById(String id) async {
    try {
      final response = await _apiClient.get('/staff/users/$id');

      if (response['success'] == true && response['data'] != null) {
        return UserModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Get staff statistics
  Future<StaffStatsModel> getStats() async {
    try {
      final response = await _apiClient.get('/staff/stats');

      if (response['success'] == true && response['data'] != null) {
        return StaffStatsModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }
}
