import '../api/api_client.dart';
import '../api/api_config.dart';
import '../../models/dictionary_entry_model.dart';
import '../../models/category_model.dart';

/// Dictionary service for API calls
class DictionaryService {
  static DictionaryService? _instance;
  final ApiClient _apiClient;

  DictionaryService._() : _apiClient = ApiClient.instance;

  static DictionaryService get instance {
    _instance ??= DictionaryService._();
    return _instance!;
  }

  /// Get published dictionary entries with filtering
  Future<List<DictionaryEntryModel>> getEntries({
    String? categoryId,
    String? search,
    String? difficulty,
    int limit = 20,
    int skip = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'skip': skip.toString(),
    };

    if (categoryId != null && categoryId.isNotEmpty) {
      queryParams['categoryId'] = categoryId;
    }
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    if (difficulty != null && difficulty.isNotEmpty) {
      queryParams['difficulty'] = difficulty;
    }

    final response = await _apiClient.get(
      ApiConfig.dictionaryEndpoint,
      queryParameters: queryParams,
      requiresAuth: false, // Public endpoint
    );

    if (response['success'] == true && response['data'] != null) {
      final List<dynamic> data = response['data'] as List<dynamic>;
      return data
          .map((json) => DictionaryEntryModel.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  /// Get single dictionary entry by ID
  Future<DictionaryEntryModel> getEntryById(String id) async {
    final response = await _apiClient.get(
      '${ApiConfig.dictionaryEndpoint}/$id',
      requiresAuth: false, // Public endpoint
    );

    if (response['success'] == true && response['data'] != null) {
      return DictionaryEntryModel.fromJson(
          response['data'] as Map<String, dynamic>);
    }

    throw Exception('Entry not found');
  }

  /// Get popular entries
  Future<List<DictionaryEntryModel>> getPopularEntries({int limit = 10}) async {
    final response = await _apiClient.get(
      '${ApiConfig.dictionaryEndpoint}/popular',
      queryParameters: {'limit': limit.toString()},
      requiresAuth: false,
    );

    if (response['success'] == true && response['data'] != null) {
      final List<dynamic> data = response['data'] as List<dynamic>;
      return data
          .map((json) => DictionaryEntryModel.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  /// Create draft entry (STAFF/ADMIN only)
  Future<DictionaryEntryModel> createEntry({
    required String word,
    required String definition,
    required String videoUrl,
    required String categoryId,
    String? thumbnailUrl,
    List<String>? imageUrls,
    List<String>? tags,
    String? difficulty,
    String? usageExample,
    String? notes,
  }) async {
    final response = await _apiClient.post(
      ApiConfig.dictionaryEndpoint,
      body: {
        'word': word,
        'definition': definition,
        'videoUrl': videoUrl,
        'categoryId': categoryId,
        'thumbnailUrl': ?thumbnailUrl,
        'imageUrls': ?imageUrls,
        'tags': ?tags,
        'difficulty': ?difficulty,
        'usageExample': ?usageExample,
        'notes': ?notes,
      },
      requiresAuth: true,
    );

    if (response['success'] == true && response['data'] != null) {
      return DictionaryEntryModel.fromJson(
          response['data'] as Map<String, dynamic>);
    }

    throw Exception('Failed to create entry');
  }

  /// Update entry (STAFF/ADMIN only)
  Future<DictionaryEntryModel> updateEntry({
    required String id,
    String? word,
    String? definition,
    String? videoUrl,
    String? categoryId,
    String? thumbnailUrl,
    List<String>? imageUrls,
    List<String>? tags,
    String? difficulty,
    String? usageExample,
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    
    if (word != null) body['word'] = word;
    if (definition != null) body['definition'] = definition;
    if (videoUrl != null) body['videoUrl'] = videoUrl;
    if (categoryId != null) body['categoryId'] = categoryId;
    if (thumbnailUrl != null) body['thumbnailUrl'] = thumbnailUrl;
    if (imageUrls != null) body['imageUrls'] = imageUrls;
    if (tags != null) body['tags'] = tags;
    if (difficulty != null) body['difficulty'] = difficulty;
    if (usageExample != null) body['usageExample'] = usageExample;
    if (notes != null) body['notes'] = notes;

    final response = await _apiClient.patch(
      '${ApiConfig.dictionaryEndpoint}/$id',
      body: body,
      requiresAuth: true,
    );

    if (response['success'] == true && response['data'] != null) {
      return DictionaryEntryModel.fromJson(
          response['data'] as Map<String, dynamic>);
    }

    throw Exception('Failed to update entry');
  }

  /// Publish entry (ADMIN only)
  Future<DictionaryEntryModel> publishEntry(String id) async {
    final response = await _apiClient.post(
      '${ApiConfig.dictionaryEndpoint}/$id/publish',
      requiresAuth: true,
    );

    if (response['success'] == true && response['data'] != null) {
      return DictionaryEntryModel.fromJson(
          response['data'] as Map<String, dynamic>);
    }

    throw Exception('Failed to publish entry');
  }

  /// Archive entry (ADMIN only)
  Future<DictionaryEntryModel> archiveEntry(String id) async {
    final response = await _apiClient.post(
      '${ApiConfig.dictionaryEndpoint}/$id/archive',
      requiresAuth: true,
    );

    if (response['success'] == true && response['data'] != null) {
      return DictionaryEntryModel.fromJson(
          response['data'] as Map<String, dynamic>);
    }

    throw Exception('Failed to archive entry');
  }

  /// Get all categories
  Future<List<CategoryModel>> getCategories() async {
    final response = await _apiClient.get(
      ApiConfig.categoriesEndpoint,
      requiresAuth: false,
    );

    if (response['success'] == true && response['data'] != null) {
      final List<dynamic> data = response['data'] as List<dynamic>;
      return data
          .map((json) => CategoryModel.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  /// Get category by slug
  Future<CategoryModel> getCategoryBySlug(String slug) async {
    final response = await _apiClient.get(
      '${ApiConfig.categoriesEndpoint}/$slug',
      requiresAuth: false,
    );

    if (response['success'] == true && response['data'] != null) {
      return CategoryModel.fromJson(response['data'] as Map<String, dynamic>);
    }

    throw Exception('Category not found');
  }
}
