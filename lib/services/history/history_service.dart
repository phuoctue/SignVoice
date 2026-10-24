import '../../models/history_entry_model.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Service for managing user history
class HistoryService {
  static HistoryService? _instance;
  final ApiClient _apiClient;

  HistoryService._() : _apiClient = ApiClient.instance;

  static HistoryService get instance {
    _instance ??= HistoryService._();
    return _instance!;
  }

  /// Get user history
  Future<List<HistoryEntryModel>> getHistory() async {
    try {
      final response = await _apiClient.get('/history');

      if (response['success'] == true && response['data'] != null) {
        final List<dynamic> items = response['data'] as List;
        return items.map((json) => HistoryEntryModel.fromJson(json)).toList();
      }

      throw ApiException(message: 'Invalid response format');
    } catch (e) {
      rethrow;
    }
  }

  /// Clear all history
  Future<void> clearHistory() async {
    try {
      final response = await _apiClient.delete('/history');

      if (response['success'] != true) {
        throw ApiException(message: 'Failed to clear history');
      }
    } catch (e) {
      rethrow;
    }
  }
}
