import 'package:flutter/foundation.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';

class LearningPageController extends ChangeNotifier {
  LearningPageController({required this.loadPage, required this.errorMessage});

  final Future<LearningPage> Function(int page) loadPage;
  final String errorMessage;
  LearningPage? _data;
  String? _error;
  int _page = 1, _request = 0;
  bool _loading = true, _disposed = false;

  LearningPage? get data => _data;
  String? get error => _error;
  int get page => _page;
  bool get loading => _loading;

  Future<void> load({int? page}) async {
    if (_disposed) return;
    if (page != null) _page = page < 1 ? 1 : page;
    final request = ++_request;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      while (true) {
        final result = await loadPage(_page);
        if (_disposed || request != _request) return;
        final lastPage = result.pages < 1 ? 1 : result.pages;
        if (_page > lastPage) {
          _page = lastPage;
          continue;
        }
        _data = result;
        break;
      }
    } catch (e) {
      if (!_disposed && request == _request) {
        _error = e is ApiException ? e.message : errorMessage;
      }
    } finally {
      if (!_disposed && request == _request) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
