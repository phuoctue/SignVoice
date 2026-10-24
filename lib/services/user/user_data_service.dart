import '../api/api_client.dart';

typedef UserRecord = Map<String, dynamic>;

class UserDataService {
  UserDataService({ApiClient? apiClient})
    : api = apiClient ?? ApiClient.instance;
  final ApiClient api;
  UserRecord record(dynamic value) => Map<String, dynamic>.from(value as Map);
  Future<UserRecord> profile() async =>
      record((await api.get('/users/profile'))['data']);
  Future<UserRecord> settings() async =>
      record((await api.get('/users/settings'))['data']);
  Future<UserRecord> saveProfile(UserRecord body) async =>
      record((await api.patch('/users/profile', body: body))['data']);
  Future<UserRecord> saveSettings(UserRecord body) async =>
      record((await api.patch('/users/settings', body: body))['data']);
  Future<UserRecord> conversations({
    int page = 1,
    String search = '',
    String? direction,
    bool? favorite,
  }) async => record(
    (await api.get(
      '/conversations',
      queryParameters: {
        'page': '$page',
        'limit': '20',
        if (search.isNotEmpty) 'search': search,
        'direction': ?direction,
        if (favorite != null) 'favorite': '$favorite',
      },
    ))['data'],
  );
  Future<List<UserRecord>> favorites() async {
    final result = <UserRecord>[];
    var skip = 0;
    while (true) {
      final response = await api.get(
        '/favorites',
        queryParameters: {'limit': '100', 'skip': '$skip'},
      );
      final items = (response['data'] as List).map(record).toList();
      result.addAll(items);
      skip += items.length;
      if (items.isEmpty || skip >= (response['pagination']['total'] as num)) {
        return result;
      }
    }
  }

  Future<UserRecord> saveConversation(String content, String direction) async =>
      record(
        (await api.post(
          '/conversations',
          body: {'content': content, 'direction': direction},
        ))['data'],
      );
  Future<UserRecord> conversation(String id) async =>
      record((await api.get('/conversations/$id'))['data']);
  Future<UserRecord> updateConversation(String id, UserRecord body) async =>
      record((await api.patch('/conversations/$id', body: body))['data']);
  Future<void> deleteConversation(String id) async {
    await api.delete('/conversations/$id');
  }

  Future<void> clearHistory() async {
    await api.delete('/conversations');
  }

  Future<void> setFavorite(String id, bool enabled) async {
    if (enabled) {
      await api.post('/favorites', body: {'entryId': id});
    } else {
      await api.delete('/favorites/$id');
    }
  }

  Future<UserRecord> dictionaryEntry(String id) async =>
      record((await api.get('/dictionary/$id'))['data']);
  Future<List<UserRecord>> sessions() async =>
      ((await api.get('/users/sessions'))['data'] as List).map(record).toList();
  Future<bool> revokeSession(String id) async =>
      (await api.delete('/users/sessions/$id'))['data']['revokedCurrent'] ==
      true;
  Future<UserRecord> exportData() async =>
      record((await api.get('/users/data/export'))['data']);
  Future<void> clearData() async {
    await api.delete('/users/data', body: {'confirm': true});
  }

  Future<void> deleteAccount({String? password}) async {
    await api.delete(
      '/users/account',
      body: {'confirm': true, 'currentPassword': ?password},
    );
  }
}
