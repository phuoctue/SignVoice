import 'dart:convert';
import 'dart:math';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../media/managed_media.dart';

typedef LearningRecord = Map<String, dynamic>;

class LearningPage {
  LearningPage({
    required this.items,
    this.page = 1,
    this.pages = 1,
    this.total = 0,
    this.pageSize = 10,
    this.summary = const {},
    this.topic = const {},
    this.enrolled = false,
  });
  factory LearningPage.fromJson(LearningRecord data) {
    final pagination = data['pagination'] as Map? ?? {};
    final items = (data['items'] as List? ?? [])
        .map((v) => LearningRecord.from(v as Map))
        .toList();
    primeImagePreviews(items);
    return LearningPage(
      items: items,
      page: (pagination['page'] as num? ?? 1).toInt(),
      pages: (pagination['pages'] as num? ?? 1).toInt(),
      total: (pagination['total'] as num? ?? 0).toInt(),
      pageSize: (pagination['pageSize'] as num? ?? 10).toInt(),
      summary: LearningRecord.from(data['summary'] as Map? ?? {}),
      topic: LearningRecord.from(data['topic'] as Map? ?? {}),
      enrolled: data['enrolled'] == true,
    );
  }
  final List<LearningRecord> items;
  final int page, pages, total, pageSize;
  final LearningRecord summary, topic;
  final bool enrolled;
}

class LearningService {
  LearningService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;
  final _pages = <String, ({LearningPage page, DateTime saved})>{};
  final _pending = <String, Future<LearningPage>>{};
  final _pendingAi = <String, Future<LearningRecord>>{};
  int _cacheEpoch = -1, _revision = 0;

  String _pageKey(String path, Map<String, String> query) =>
      Uri(path: path, queryParameters: query).toString();
  void _checkCacheOwner() {
    if (_cacheEpoch != _client.sessionEpoch) {
      _cacheEpoch = _client.sessionEpoch;
      invalidatePages();
    }
  }

  /// Private learning state lives only in memory and is discarded on account
  /// changes and acknowledged writes. Refresh buttons explicitly invalidate it.
  void invalidatePages() {
    _revision++;
    _pages.clear();
    _pending.clear();
    _pendingAi.clear();
  }

  LearningPage? cachedPage(String path, Map<String, String> query) {
    _checkCacheOwner();
    final key = _pageKey(path, query), entry = _pages[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.saved) > const Duration(minutes: 2)) {
      _pages.remove(key);
      return null;
    }
    return entry.page;
  }

  Future<LearningPage> _page(String path, Map<String, String> query) async {
    _checkCacheOwner();
    final epoch = _cacheEpoch, revision = _revision;
    final key = _pageKey(path, query);
    final cacheable =
        path == 'topics' || path.startsWith('topics/') || path == 'progress';
    final cached = cacheable ? _pages[key] : null;
    if (cached != null &&
        DateTime.now().difference(cached.saved) < const Duration(seconds: 10)) {
      return cached.page;
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final request = _fetchPage(path, query, epoch, revision, key, cacheable);
    _pending[key] = request;
    try {
      return await request;
    } finally {
      if (identical(_pending[key], request)) _pending.remove(key);
    }
  }

  Future<LearningPage> _fetchPage(
    String path,
    Map<String, String> query,
    int epoch,
    int revision,
    String key,
    bool cacheable,
  ) async {
    final response = await _client.get(
      '/learning/$path',
      queryParameters: query,
    );
    if (epoch != _client.sessionEpoch) {
      throw ApiException(
        message: 'Tài khoản đã thay đổi. Vui lòng mở lại danh sách.',
        code: 'SESSION_CHANGED',
      );
    }
    if (revision != _revision) return _page(path, query);
    final page = LearningPage.fromJson(
      LearningRecord.from(response['data'] as Map),
    );
    if (cacheable) {
      _pages.remove(key);
      while (_pages.length >= 8) {
        _pages.remove(_pages.keys.first);
      }
      _pages[key] = (page: page, saved: DateTime.now());
    }
    return page;
  }

  Future<LearningPage> topics({int page = 1, String search = ''}) =>
      _page('topics', {'page': '$page', 'search': search});
  Future<LearningPage> progress({int page = 1, String stage = 'ALL'}) =>
      _page('progress', {'page': '$page', 'stage': stage});
  Future<LearningPage> topic(String id, {int page = 1, String stage = 'ALL'}) =>
      _page('topics/$id', {'page': '$page', 'stage': stage});
  Future<LearningPage> myWords({int page = 1, String search = ''}) =>
      _page('my-words', {'page': '$page', 'search': search});
  Future<LearningRecord> insights({int days = 7, int page = 1}) async {
    final response = await _client.get(
      '/learning/insights',
      queryParameters: {'days': '$days', 'page': '$page'},
    );
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> todayProgress() async {
    final response = await _client.get('/learning/today');
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningPage> activity({
    required String date,
    String kind = 'learned',
    int page = 1,
  }) => _page('activity', {'date': date, 'kind': kind, 'page': '$page'});

  Future<void> saveGoals({
    required int newWords,
    required int reviewWords,
  }) async {
    await _client.patch(
      '/learning/goals',
      body: {'newWords': newWords, 'reviewWords': reviewWords},
    );
  }

  Future<LearningPage> history({
    int page = 1,
    String search = '',
    String? entryId,
  }) => _page('history', {
    'page': '$page',
    'search': search,
    'entryId': ?entryId,
  });
  Future<void> start(String id) async {
    await _client.post('/learning/topics/$id/start');
    invalidatePages();
  }

  Future<void> rate(String id, String stage) async {
    await _client.patch('/learning/words/$id/progress', body: {'stage': stage});
    invalidatePages();
  }

  Future<LearningRecord> startQuiz(String topicId) async {
    final response = await _client.post(
      '/learning/topics/$topicId/quiz',
      body: {},
    );
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> quiz(String id) async {
    final response = await _client.get('/learning/quizzes/$id');
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> saveQuizAnswers(
    String id,
    List<String> answers,
  ) async {
    final response = await _client.patch(
      '/learning/quizzes/$id/answers',
      body: {'answers': answers},
    );
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> saveQuizCapture(
    String id, {
    required String entryId,
    required String recognizedLabel,
  }) async {
    final response = await _client.patch(
      '/learning/quizzes/$id/captures',
      body: {'entryId': entryId, 'recognizedLabel': recognizedLabel},
    );
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> submitQuiz(String id) async {
    final response = await _client.post(
      '/learning/quizzes/$id/submit',
      body: {},
    );
    invalidatePages();
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> coach() => _advice('coach');

  Future<LearningRecord> analyzeProgress() => _advice('analysis');

  Future<LearningRecord> _advice(String feature) async {
    _checkCacheOwner();
    final epoch = _cacheEpoch, revision = _revision;
    var pending = _pendingAi[feature];
    if (pending == null) {
      late final Future<LearningRecord> request;
      request = _fetchAdvice(feature, epoch, revision).whenComplete(() {
        if (identical(_pendingAi[feature], request)) _pendingAi.remove(feature);
      });
      _pendingAi[feature] = pending = request;
    }
    final result = await pending;
    // Share an in-flight generation only; each caller owns its JSON result.
    return LearningRecord.from(jsonDecode(jsonEncode(result)) as Map);
  }

  Future<LearningRecord> _fetchAdvice(
    String feature,
    int epoch,
    int revision,
  ) async {
    final random = Random.secure();
    final key = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final elapsed = Stopwatch()..start();
    dynamic response;
    for (var attempt = 0; attempt < 2; attempt++) {
      _checkAdviceOwner(epoch, revision);
      try {
        response = await _client.post(
          '/learning/$feature',
          body: {'async': true, 'requestKey': key},
        );
        break;
      } on NetworkException {
        if (attempt == 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      } on ServerException {
        if (attempt == 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    while (true) {
      _checkAdviceOwner(epoch, revision);
      final job = LearningRecord.from(response['data'] as Map);
      // Retain compatibility with servers that return the completed DTO directly.
      if (job['state'] == null) return job;
      if (job['state'] == 'completed' && job['result'] is Map) {
        return LearningRecord.from(job['result'] as Map);
      }
      if (job['state'] == 'failed') {
        throw ApiException(
          message: 'Chưa hoàn tất phân tích AI. Vui lòng thử lại.',
        );
      }
      if (job['state'] != 'pending' || job['id'] is! String) {
        throw ApiException(
          message: 'Trạng thái phân tích không hợp lệ. Vui lòng thử lại.',
        );
      }
      if (elapsed.elapsed > const Duration(minutes: 2)) {
        throw ApiException(
          message:
              'AI đang xử lý lâu hơn dự kiến. Vui lòng thử lại sau ít phút.',
          code: 'LEARNING_AI_TIMEOUT',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      _checkAdviceOwner(epoch, revision);
      try {
        response = await _client.get(
          '/learning/ai-jobs/${Uri.encodeComponent(job['id'] as String)}',
        );
      } on NetworkException {
        // Keep the job ID so a brief mobile disconnect never restarts inference.
      } on ServerException {
        // A transient gateway error can be retried with the same private job ID.
      }
    }
  }

  void _checkAdviceOwner(int epoch, int revision) {
    _client.checkSession(epoch);
    if (revision != _revision) {
      throw ApiException(
        message: 'Tiến độ đã thay đổi. Vui lòng phân tích lại.',
        code: 'LEARNING_CHANGED',
      );
    }
  }

  Future<void> saveWord(LearningRecord word, {String? id}) async {
    if (id == null) {
      await _client.post('/learning/my-words', body: word);
    } else {
      await _client.patch('/learning/my-words/$id', body: word);
    }
  }

  Future<void> deleteWord(String id) async {
    await _client.delete('/learning/my-words/$id');
  }
}
