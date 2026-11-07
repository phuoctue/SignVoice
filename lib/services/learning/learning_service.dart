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
  final _quizHandoff = <String, ({LearningRecord quiz, DateTime saved})>{};
  final _collectionCache = <String, ({LearningRecord value, DateTime saved})>{};
  final _collectionPending = <String, Future<LearningRecord>>{};
  int _cacheEpoch = -1, _revision = 0;
  int _catalogEpoch = -1;

  String _pageKey(String path, Map<String, String> query) =>
      Uri(path: path, queryParameters: query).toString();
  void _checkCacheOwner() {
    if (_cacheEpoch != _client.sessionEpoch ||
        _catalogEpoch != _client.libraryChanged.value) {
      _cacheEpoch = _client.sessionEpoch;
      _catalogEpoch = _client.libraryChanged.value;
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
    _quizHandoff.clear();
    _collectionCache.clear();
    _collectionPending.clear();
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
    int pageSize = 10,
    String search = '',
    String? entryId,
  }) => _page('history', {
    'page': '$page',
    if (pageSize != 10) 'pageSize': '$pageSize',
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

  Future<LearningRecord> startQuiz(String topicId) =>
      _startTopicQuiz(topicId, 'VIDEO_RECALL');
  Future<LearningRecord> startMatchQuiz(String topicId) =>
      _startTopicQuiz(topicId, 'VIDEO_MATCH');

  Future<LearningRecord> _startTopicQuiz(String topicId, String format) async {
    _checkCacheOwner();
    final epoch = _client.sessionEpoch;
    final response = await _client.post(
      '/learning/topics/$topicId/quiz',
      body: {'format': format},
    );
    _client.checkSession(epoch);
    final quiz = LearningRecord.from(response['data'] as Map);
    _quizHandoff.clear();
    _quizHandoff['${quiz['_id']}'] = (quiz: quiz, saved: DateTime.now());
    return LearningRecord.from(quiz);
  }

  String collectionKey(String path, {int page = 1, String search = ''}) => Uri(
    path: path,
    queryParameters: {'page': '$page', 'search': search},
  ).toString();
  LearningRecord? cachedCollection(
    String path, {
    int page = 1,
    String search = '',
  }) {
    _checkCacheOwner();
    final entry =
        _collectionCache[collectionKey(path, page: page, search: search)];
    if (entry == null ||
        DateTime.now().difference(entry.saved) > const Duration(minutes: 2)) {
      return null;
    }
    return LearningRecord.from(jsonDecode(jsonEncode(entry.value)) as Map);
  }

  Future<LearningRecord> collectionRead(
    String path, {
    int page = 1,
    String search = '',
  }) async {
    _checkCacheOwner();
    final key = collectionKey(path, page: page, search: search),
        epoch = _client.sessionEpoch,
        revision = _revision;
    final cached = _collectionCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.saved) < const Duration(seconds: 10)) {
      return LearningRecord.from(jsonDecode(jsonEncode(cached.value)) as Map);
    }
    var request = _collectionPending[key];
    if (request == null) {
      late final Future<LearningRecord> fetch;
      fetch =
          () async {
            final response = await _client.get(
              path,
              queryParameters: {'page': '$page', 'search': search},
              requiresAuth:
                  path != '/shared-collections' &&
                  !path.startsWith('/shared-collections/'),
            );
            if (epoch != _client.sessionEpoch &&
                (path == '/shared-collections' ||
                    path.startsWith('/shared-collections/'))) {
              // Public data survives session restoration, but must not populate
              // a cache belonging to a different account.
              return LearningRecord.from(response['data'] as Map);
            }
            _client.checkSession(epoch);
            _checkCacheOwner();
            if (revision != _revision) {
              throw ApiException(
                message: 'Danh sách đã thay đổi. Hãy tải lại.',
                code: 'COLLECTION_CHANGED',
              );
            }
            final value = LearningRecord.from(response['data'] as Map);
            primeImagePreviews(
              (value['items'] as List? ?? []).map(
                (item) => LearningRecord.from(item as Map),
              ),
            );
            if (_collectionCache.length >= 24) {
              _collectionCache.remove(_collectionCache.keys.first);
            }
            _collectionCache[key] = (value: value, saved: DateTime.now());
            return value;
          }().whenComplete(() {
            if (identical(_collectionPending[key], fetch)) {
              _collectionPending.remove(key);
            }
          });
      _collectionPending[key] = request = fetch;
    }
    final value = await request;
    return LearningRecord.from(jsonDecode(jsonEncode(value)) as Map);
  }

  Future<LearningRecord> _collectionWrite(
    String method,
    String path,
    LearningRecord body,
  ) async {
    final response = await switch (method) {
      'PATCH' => _client.patch(path, body: body),
      'PUT' => _client.put(path, body: body),
      'DELETE' => _client.delete(path, body: body),
      _ => _client.post(path, body: body),
    };
    invalidatePages();
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> createCollection(
    String name,
    String description, {
    String avatarImage = '',
  }) => _collectionWrite('POST', '/sign-collections', {
    'name': name,
    'description': description,
    'avatarImage': avatarImage,
  });
  Future<LearningRecord> updateCollection(
    String id,
    String name,
    String description, {
    String? avatarImage,
  }) => _collectionWrite('PATCH', '/sign-collections/$id', {
    'name': name,
    'description': description,
    'avatarImage': ?avatarImage,
  });
  Future<LearningRecord> deleteCollection(String id) =>
      _collectionWrite('DELETE', '/sign-collections/$id', {});
  Future<LearningRecord> saveCollectionWord(
    String collectionId,
    LearningRecord word, {
    String? id,
  }) => _collectionWrite(
    id == null ? 'POST' : 'PATCH',
    '/sign-collections/$collectionId/personal-words${id == null ? '' : '/$id'}',
    word,
  );
  Future<LearningRecord> attachCollectionWords(
    String collectionId,
    List<String> wordIds,
  ) => _collectionWrite(
    'POST',
    '/sign-collections/$collectionId/personal-words/attach',
    {'wordIds': wordIds},
  );
  Future<LearningRecord> deleteCollectionWord(
    String collectionId,
    String wordId,
  ) => _collectionWrite(
    'DELETE',
    '/sign-collections/$collectionId/personal-words/$wordId',
    {},
  );
  Future<LearningRecord> collectionWord(
    String collectionId,
    String wordId,
  ) async => LearningRecord.from(
    (await _client.get(
          '/sign-collections/$collectionId/personal-words/$wordId',
        ))['data']
        as Map,
  );
  Future<LearningRecord> addCollectionEntries(
    String id,
    List<String> entries,
  ) => _collectionWrite('POST', '/sign-collections/$id/entries', {
    'entryIds': entries,
  });
  Future<LearningRecord> removeCollectionEntry(String id, String entryId) =>
      _collectionWrite('DELETE', '/sign-collections/$id/entries/$entryId', {});
  Future<LearningRecord> shareCollection(String id, bool enabled) =>
      _collectionWrite('POST', '/sign-collections/$id/share', {
        'enabled': enabled,
      });
  Future<LearningRecord> importCollection(String code) =>
      _collectionWrite('POST', '/sign-collections/import', {'code': code});
  Future<LearningRecord> publishCollection(String id, bool enabled) =>
      _collectionWrite('POST', '/sign-collections/$id/discovery', {
        'enabled': enabled,
      });
  Future<LearningRecord> reportSharedCollection(
    String code,
    String category,
    String details,
  ) => _collectionWrite('POST', '/shared-collections/$code/reports', {
    'category': category,
    'details': details,
  });
  Future<LearningRecord> requestCollectionReview(String id) =>
      _collectionWrite('POST', '/sign-collections/$id/moderation-review', {});
  Future<LearningRecord> saveSignNote(String id, String text) =>
      _collectionWrite('PUT', '/sign-notes/$id', {'text': text});
  Future<LearningRecord> signNote(String id) async => LearningRecord.from(
    (await _client.get('/sign-notes/$id'))['data'] as Map,
  );
  Future<LearningRecord> startCollectionQuiz(String id) =>
      _startCollectionQuiz(id, false);
  Future<LearningRecord> startCollectionMatchQuiz(String id) =>
      _startCollectionQuiz(id, true);
  Future<LearningRecord> _startCollectionQuiz(String id, bool matching) async {
    _checkCacheOwner();
    final epoch = _client.sessionEpoch;
    final response = await _client.post(
      '/sign-collections/$id/quiz',
      body: {if (matching) 'format': 'VIDEO_MATCH'},
    );
    _client.checkSession(epoch);
    final quiz = LearningRecord.from(response['data'] as Map);
    _quizHandoff.clear();
    _quizHandoff['${quiz['_id']}'] = (quiz: quiz, saved: DateTime.now());
    return quiz;
  }

  Future<LearningRecord> quiz(String id) async {
    _checkCacheOwner();
    // Consume the start response once, only for this authenticated session.
    // Reopening or refreshing later still fetches authoritative server state.
    final initial = _quizHandoff.remove(id);
    if (initial != null &&
        DateTime.now().difference(initial.saved) <
            const Duration(seconds: 15)) {
      return LearningRecord.from(initial.quiz);
    }
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

  Future<LearningRecord> quizHint(String id, String entryId) async {
    final response = await _client.post(
      '/learning/quizzes/$id/hint',
      body: {'entryId': entryId},
    );
    return LearningRecord.from(response['data'] as Map);
  }

  String newMatchRequestId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<LearningRecord> matchQuizPair(
    String id,
    String entryId,
    String optionId,
    String requestId,
  ) async {
    final epoch = _client.sessionEpoch;
    final response = await _client.post(
      '/learning/quizzes/$id/match',
      body: {'entryId': entryId, 'optionId': optionId, 'requestId': requestId},
    );
    _client.checkSession(epoch);
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> matchQuizHint(String id, String entryId) async {
    final epoch = _client.sessionEpoch;
    final response = await _client.post(
      '/learning/quizzes/$id/match-hint',
      body: {'entryId': entryId},
    );
    _client.checkSession(epoch);
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> checkQuizAnswer(
    String id,
    String entryId,
    String answer, {
    bool skip = false,
  }) async {
    final response = await _client.post(
      '/learning/quizzes/$id/check',
      body: {'entryId': entryId, 'answer': answer, 'skip': skip},
    );
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> assessQuizAnswer(
    String id,
    String entryId,
    String assessment,
  ) async {
    final response = await _client.post(
      '/learning/quizzes/$id/assessment',
      body: {'entryId': entryId, 'assessment': assessment},
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

  Future<LearningRecord> quizAdvice(String id) =>
      _advice('quizzes/${Uri.encodeComponent(id)}/advice');

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
