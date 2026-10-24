import '../../models/category_model.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Service for category management
class CategoryService {
  static CategoryService? _instance;
  final ApiClient _apiClient;

  CategoryService._() : _apiClient = ApiClient.instance;

  static CategoryService get instance {
    _instance ??= CategoryService._();
    return _instance!;
  }

  /// Get all categories
  Future<List<CategoryModel>> getCategories() async {
    try {
      final response = await _apiClient.get(
        '/categories',
        requiresAuth: false,
      );

      if (response['success'] == true && response['data'] != null) {
        final List<dynamic> items = response['data'] as List;
        return items.map((json) => CategoryModel.fromJson(json)).toList();
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Get category by slug
  Future<CategoryModel> getCategoryBySlug(String slug) async {
    try {
      final response = await _apiClient.get(
        '/categories/$slug',
        requiresAuth: false,
      );

      if (response['success'] == true && response['data'] != null) {
        return CategoryModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Create a new category (admin only)
  Future<CategoryModel> createCategory({
    required String name,
    required String slug,
    String? description,
    String? icon,
    int? sortOrder,
    String status = 'ACTIVE',
  }) async {
    try {
      final response = await _apiClient.post(
        '/categories',
        body: {
          'name': name,
          'slug': slug,
          'description': ?description,
          'icon': ?icon,
          'sortOrder': ?sortOrder,
          'status': status,
        },
      );

      if (response['success'] == true && response['data'] != null) {
        return CategoryModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Failed to create category');
    } catch (e) {
      rethrow;
    }
  }
}
