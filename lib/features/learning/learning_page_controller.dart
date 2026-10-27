import 'package:flutter/foundation.dart';

import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';

class LearningPageController extends ChangeNotifier {
  LearningPageController({
    required this.loadPage,
    required this.errorMessage,
    this.cachedPage,
  });

  final Future<LearningPage> Function(int page) loadPage;
  final LearningPage? Function(int page)? cachedPage;
  final String errorMessage;
  LearningPage? _data;
  String? _error;
  int _page = 1, _request = 0;
  bool _loading = true, _disposed = false;

  LearningPage? get data => _data;
  String? get error => _error;
  int get page => _page;
  bool get loading => _loading;

  /// Apply only an acknowledged server write; reconciliation can run in the
  /// background without removing the list or delaying the saved confirmation.
  void applyStage(String id, String stage, {required String filter}) {
    final data = _data;
    if (_disposed || data == null) return;
    final entry = data.items
        .where((word) => '${word['_id']}' == id)
        .firstOrNull;
    if (entry == null || entry['stage'] == stage) return;
    _request++; // An older read must not undo this acknowledged write.
    final summary = LearningRecord.from(data.summary);
    for (final (key, delta) in [
      ('${entry['stage']}'.toLowerCase(), -1),
      (stage.toLowerCase(), 1),
    ]) {
      summary[key] = ((summary[key] as num? ?? 0).toInt() + delta).clamp(
        0,
        1 << 30,
      );
    }
    final removed = filter != 'ALL' && filter != stage;
    final items = data.items
        .where((word) => !removed || '${word['_id']}' != id)
        .map(
          (word) => '${word['_id']}' == id ? {...word, 'stage': stage} : word,
        )
        .toList();
    final total = removed ? (data.total - 1).clamp(0, 1 << 30) : data.total;
    _data = LearningPage(
      items: items,
      page: data.page,
      pageSize: data.pageSize,
      pages: ((total / data.pageSize).ceil()).clamp(1, 1 << 30),
      total: total,
      summary: summary,
      topic: data.topic,
      enrolled: data.enrolled,
    );
    _loading = false;
    notifyListeners();
  }

  Future<void> load({int? page, bool background = false}) async {
    if (_disposed) return;
    if (page != null) _page = page < 1 ? 1 : page;
    final request = ++_request;
    final cached = cachedPage?.call(_page);
    if (cached != null) _data = cached;
    _loading = cached == null && (!background || _data == null);
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
