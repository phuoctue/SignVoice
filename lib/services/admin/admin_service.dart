import '../../models/user_model.dart';
import '../../models/admin_stats_model.dart';
import '../../models/session_model.dart';
import '../../models/dictionary_entry_model.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Service for admin operations
class AdminService {
  static AdminService? _instance;
  final ApiClient _apiClient;

  AdminService._() : _apiClient = ApiClient.instance;

  static AdminService get instance {
    _instance ??= AdminService._();
    return _instance!;
  }

  /// Get users with pagination and filters
  Future<Map<String, dynamic>> getUsers({
    int page = 1,
    int limit = 20,
    String? search,
    String? role,
    String? status,
    String? accountType,
    String? sortBy,
    String? order,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (search != null && search.isNotEmpty) 'search': search,
        'role': ?role,
        'status': ?status,
        'accountType': ?accountType,
        'sortBy': ?sortBy,
        'order': ?order,
      };

      final response = await _apiClient.get(
        '/admin/users',
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
      final response = await _apiClient.get('/admin/users/$id');

      if (response['success'] == true && response['data'] != null) {
        return UserModel.fromJson(response['data']['user']);
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Update user
  Future<UserModel> updateUser(String id, Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.patch(
        '/admin/users/$id',
        body: data,
      );

      if (response['success'] == true && response['data'] != null) {
        return UserModel.fromJson(response['data']['user']);
      }

      throw ApiException(message: 'Failed to update user');
    } catch (e) {
      rethrow;
    }
  }

  /// Delete user
  Future<void> deleteUser(String id) async {
    try {
      final response = await _apiClient.delete('/admin/users/$id');

      if (response['success'] != true) {
        throw ApiException(message: 'Failed to delete user');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Suspend user
  Future<UserModel> suspendUser(String id, String reason) async {
    try {
      final response = await _apiClient.post(
        '/admin/users/$id/suspend',
        body: {'reason': reason},
      );

      if (response['success'] == true && response['data'] != null) {
        return UserModel.fromJson(response['data']['user']);
      }

      throw ApiException(message: 'Failed to suspend user');
    } catch (e) {
      rethrow;
    }
  }

  /// Activate user
  Future<UserModel> activateUser(String id) async {
    try {
      final response = await _apiClient.post('/admin/users/$id/activate');

      if (response['success'] == true && response['data'] != null) {
        return UserModel.fromJson(response['data']['user']);
      }

      throw ApiException(message: 'Failed to activate user');
    } catch (e) {
      rethrow;
    }
  }

  /// Get system statistics
  Future<AdminStatsModel> getStats() async {
    try {
      final response = await _apiClient.get('/admin/stats');

      if (response['success'] == true && response['data'] != null) {
        return AdminStatsModel.fromJson(response['data']['stats']);
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Get pending content
  Future<Map<String, dynamic>> getPendingContent({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      final response = await _apiClient.get(
        '/admin/content/pending',
        queryParameters: queryParams,
      );

      if (response['success'] == true && response['data'] != null) {
        final List<dynamic> items = response['data']['entries'] ?? [];
        final entries =
            items.map((json) => DictionaryEntryModel.fromJson(json)).toList();

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

  /// Get active sessions
  Future<Map<String, dynamic>> getSessions({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      final response = await _apiClient.get(
        '/admin/sessions',
        queryParameters: queryParams,
      );

      if (response['success'] == true && response['data'] != null) {
        final List<dynamic> items = response['data']['sessions'] ?? [];
        final sessions =
            items.map((json) => SessionModel.fromJson(json)).toList();

        return {
          'sessions': sessions,
          'pagination': response['data']['pagination'] ?? {},
        };
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Terminate session
  Future<void> terminateSession(String sessionId) async {
    try {
      final response = await _apiClient.delete('/admin/sessions/$sessionId');

      if (response['success'] != true) {
        throw ApiException(message: 'Failed to terminate session');
      }
    } catch (e) {
      rethrow;
    }
  }
}
