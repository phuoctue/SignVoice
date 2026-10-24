import '../../models/favorite_model.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Service for managing user favorites
class FavoritesService {
  static FavoritesService? _instance;
  final ApiClient _apiClient;

  FavoritesService._() : _apiClient = ApiClient.instance;

  static FavoritesService get instance {
    _instance ??= FavoritesService._();
    return _instance!;
  }

  /// Get all user favorites
  Future<List<FavoriteModel>> getFavorites() async {
    try {
      final response = await _apiClient.get('/favorites');

      if (response['success'] == true && response['data'] != null) {
        final List<dynamic> items = response['data'] as List;
        return items.map((json) => FavoriteModel.fromJson(json)).toList();
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Add a dictionary entry to favorites
  Future<FavoriteModel> addFavorite(String entryId) async {
    try {
      final response = await _apiClient.post(
        '/favorites',
        body: {'entryId': entryId},
      );

      if (response['success'] == true && response['data'] != null) {
        return FavoriteModel.fromJson(response['data']);
      }

      throw ApiException(message: 'Failed to add favorite');
    } catch (e) {
      rethrow;
    }
  }

  /// Remove a favorite by entry ID
  Future<void> removeFavorite(String entryId) async {
    try {
      final response = await _apiClient.delete('/favorites/$entryId');

      if (response['success'] != true) {
        throw ApiException(message: 'Failed to remove favorite');
      }
    } catch (e) {
      rethrow;
    }
  }
}
