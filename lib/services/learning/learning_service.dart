import '../api/api_client.dart';

typedef LearningRecord = Map<String, dynamic>;

class LearningPage {
  LearningPage({
    required this.items,
    this.page = 1,
    this.pages = 1,
    this.total = 0,
    this.summary = const {},
    this.topic = const {},
    this.enrolled = false,
  });
  factory LearningPage.fromJson(LearningRecord data) {
    final pagination = data['pagination'] as Map? ?? {};
    return LearningPage(
      items: (data['items'] as List? ?? [])
          .map((v) => LearningRecord.from(v as Map))
          .toList(),
      page: (pagination['page'] as num? ?? 1).toInt(),
      pages: (pagination['pages'] as num? ?? 1).toInt(),
      total: (pagination['total'] as num? ?? 0).toInt(),
      summary: LearningRecord.from(data['summary'] as Map? ?? {}),
      topic: LearningRecord.from(data['topic'] as Map? ?? {}),
      enrolled: data['enrolled'] == true,
    );
  }
  final List<LearningRecord> items;
  final int page, pages, total;
  final LearningRecord summary, topic;
  final bool enrolled;
}

class LearningService {
  LearningService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;
  Future<LearningPage> _page(String path, Map<String, String> query) async {
    final response = await _client.get(
      '/learning/$path',
      queryParameters: query,
    );
    return LearningPage.fromJson(LearningRecord.from(response['data'] as Map));
  }

  Future<LearningPage> topics({int page = 1, String search = ''}) =>
      _page('topics', {'page': '$page', 'search': search});
  Future<LearningPage> progress({int page = 1, String stage = 'ALL'}) =>
      _page('progress', {'page': '$page', 'stage': stage});
  Future<LearningPage> topic(String id, {int page = 1, String stage = 'ALL'}) =>
      _page('topics/$id', {'page': '$page', 'stage': stage});
  Future<LearningPage> myWords({int page = 1, String search = ''}) =>
      _page('my-words', {'page': '$page', 'search': search});
  Future<void> start(String id) async {
    await _client.post('/learning/topics/$id/start');
  }

  Future<void> rate(String id, String stage) async {
    await _client.patch('/learning/words/$id/progress', body: {'stage': stage});
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
    return LearningRecord.from(response['data'] as Map);
  }

  Future<LearningRecord> coach() async {
    final response = await _client.post('/learning/coach', body: {});
    return LearningRecord.from(response['data'] as Map);
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
