import '../api/api_client.dart';
import '../api/api_exception.dart';

typedef UserRecord = Map<String, dynamic>;

class UserBootstrap {
  const UserBootstrap({
    required this.profile,
    required this.settings,
    required this.conversations,
    required this.favorites,
  });
  final UserRecord profile, settings, conversations;
  final List<UserRecord> favorites;
  factory UserBootstrap.fromJson(UserRecord data) => UserBootstrap(
    profile: Map<String, dynamic>.from(data['profile'] as Map),
    settings: Map<String, dynamic>.from(data['settings'] as Map),
    conversations: Map<String, dynamic>.from(data['conversations'] as Map),
    favorites: (data['favorites'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(),
  );
}

class StartupUserDataService extends UserDataService {
  StartupUserDataService({super.apiClient});
  @override
  Future<UserBootstrap> bootstrap() async {
    try {
      return UserBootstrap.fromJson(
        record((await api.get('/users/bootstrap'))['data']),
      );
    } on ApiException catch (error) {
      // Permit an APK to connect to the previous backend during rollout.
      if (error.statusCode != 404) rethrow;
      return super.bootstrap();
    }
  }
}

class UserDataService {
  UserDataService({ApiClient? apiClient})
    : api = apiClient ?? ApiClient.instance;
  final ApiClient api;
  Future<UserBootstrap> bootstrap() async {
    final data = await Future.wait<dynamic>([
      profile(),
      settings(),
      conversations(),
      favorites(),
    ]);
    return UserBootstrap(
      profile: data[0] as UserRecord,
      settings: data[1] as UserRecord,
      conversations: data[2] as UserRecord,
      favorites: data[3] as List<UserRecord>,
    );
  }

  UserRecord record(dynamic value) => Map<String, dynamic>.from(value as Map);
  Future<UserRecord> profile() async =>
      record((await api.get('/users/profile'))['data']);
  Future<UserRecord> settings() async =>
      record((await api.get('/users/settings'))['data']);
  Future<UserRecord> notifications() async =>
      record((await api.get('/users/notifications'))['data']);
  Future<UserRecord> testPush() async =>
      record((await api.post('/users/notifications/test', body: {}))['data']);
  Future<void> readNotification(String id) async {
    await api.patch(
      '/users/notifications/${Uri.encodeComponent(id)}',
      body: {'read': true},
    );
  }

  Future<void> registerNotificationDevice(String token, String platform) async {
    await api.post(
      '/users/notification-devices',
      body: {'token': token, 'platform': platform},
    );
  }

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
