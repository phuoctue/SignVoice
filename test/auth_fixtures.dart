import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/auth/auth_service.dart';
import 'package:sign_voice/services/storage/token_store.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

class DemoLearningService extends LearningService {
  static const topicId = '000000000000000000000001';
  bool enrolled = false;
  final Map<String, String> ratings = {};
  final List<LearningRecord> personal = [];
  @override
  Future<LearningPage> topics({int page = 1, String search = ''}) async =>
      LearningPage(
        items: [
          if (search.isEmpty || 'Chào hỏi'.contains(search))
            {
              '_id': topicId,
              'name': 'Chào hỏi',
              'wordCount': signs.length,
              'learnerCount': enrolled ? 1 : 0,
              'enrolled': enrolled,
            },
        ],
        total: 1,
      );
  List<LearningRecord> get words => [
    for (var i = 0; i < signs.length; i++)
      {
        '_id': '${i + 10}'.padLeft(24, '0'),
        'word': signs[i].name,
        'definition': signs[i].meaning,
        'usageExample': signs[i].example,
        'stage': ratings['${i + 10}'.padLeft(24, '0')] ?? 'LEARNING',
      },
  ];
  LearningRecord get counts => {
    'total': words.length,
    'learning': words.where((w) => w['stage'] == 'LEARNING').length,
    'remembered': words.where((w) => w['stage'] == 'REMEMBERED').length,
    'review': words.where((w) => w['stage'] == 'REVIEW').length,
  };
  @override
  Future<LearningPage> topic(
    String id, {
    int page = 1,
    String stage = 'ALL',
  }) async {
    final filtered = words
        .where((w) => stage == 'ALL' || w['stage'] == stage)
        .toList();
    return LearningPage(
      items: filtered,
      total: filtered.length,
      topic: {'_id': id, 'name': 'Chào hỏi', 'learnerCount': enrolled ? 1 : 0},
      enrolled: enrolled,
      summary: counts,
    );
  }

  @override
  Future<void> start(String id) async {
    enrolled = true;
  }

  @override
  Future<void> rate(String id, String stage) async {
    ratings[id] = stage;
  }

  @override
  Future<LearningPage> progress({int page = 1, String stage = 'ALL'}) async =>
      LearningPage(
        items: enrolled
            ? [
                {
                  'topic': {'_id': topicId, 'name': 'Chào hỏi'},
                  'summary': counts,
                },
              ]
            : [],
        summary: enrolled ? counts : {},
        total: enrolled ? 1 : 0,
      );
  @override
  Future<LearningPage> myWords({int page = 1, String search = ''}) async =>
      LearningPage(
        items: personal.where((w) => '${w['word']}'.contains(search)).toList(),
        total: personal.length,
      );
  @override
  Future<void> saveWord(LearningRecord word, {String? id}) async {
    if (id != null) {
      personal.removeWhere((w) => w['_id'] == id);
    }
    personal.add({
      ...word,
      '_id': id ?? '${personal.length + 100}'.padLeft(24, '0'),
    });
  }

  @override
  Future<void> deleteWord(String id) async {
    personal.removeWhere((w) => w['_id'] == id);
  }

  @override
  Future<LearningRecord> coach() async => {
    'source': 'rules',
    'advice': 'Học từng nhóm nhỏ và ôn lại từ đã chọn.',
  };
}

class DemoDictionaryService extends AdminWorkspaceService {
  @override
  Future<List<AdminRecord>> activeCategories() async => signs
      .map((sign) => sign.category)
      .toSet()
      .map((name) => {'_id': name, 'name': name})
      .toList();
  @override
  Future<AdminPageData> published({
    int page = 1,
    String search = '',
    String? categoryId,
    String sort = 'word_asc',
  }) async => AdminPageData(
    signs
        .where(
          (sign) =>
              (search.isEmpty || sign.name.contains(search)) &&
              (categoryId == null || sign.category == categoryId),
        )
        .map(
          (sign) => {
            '_id': sign.name,
            'word': sign.name,
            'definition': sign.meaning,
            'usageExample': sign.example,
            'categoryId': {'name': sign.category},
          },
        )
        .toList(),
    1,
    1,
    signs.length,
  );
}

class MemoryTokenStore implements TokenStore {
  String? accessToken;
  String? refreshToken;
  String? role;
  int writes = 0;
  @override
  Future<String?> getAccessToken() async => accessToken;
  @override
  Future<String?> getRefreshToken() async => refreshToken;
  @override
  Future<String?> getUserRole() async => role;
  @override
  Future<bool> isAuthenticated() async => accessToken != null;
  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    writes++;
  }

  @override
  Future<void> saveUserInfo({
    required String userId,
    required String role,
  }) async => this.role = role;
  @override
  Future<void> clearAll() async {
    accessToken = null;
    refreshToken = null;
    role = null;
  }
}

UserModel testUser({UserRole role = UserRole.user, bool guest = false}) =>
    UserModel(
      id: '0123456789abcdef01234567',
      email: guest ? null : 'user@example.com',
      displayName: 'Test User',
      accountType: guest ? AccountType.guest : AccountType.local,
      role: role,
      status: AccountStatus.active,
      isGuest: guest,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class FakeAuthService extends AuthService {
  FakeAuthService({this.restoredUser, this.role = UserRole.user})
    : super(
        apiClient: ApiClient(
          client: MockClient((_) async => http.Response('{}', 500)),
          tokenStorage: MemoryTokenStore(),
          useRefreshCookie: false,
        ),
        tokenStorage: MemoryTokenStore(),
      );
  final UserModel? restoredUser;
  final UserRole role;
  bool failLogin = false;
  @override
  Future<UserModel?> restoreSession() async => restoredUser;
  @override
  Future<UserModel> getCurrentUser() async =>
      restoredUser ?? testUser(role: role);
  @override
  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    if (failLogin) throw Exception('Invalid credentials');
    return testUser(role: role);
  }

  @override
  Future<UserModel> register({
    required String email,
    required String password,
    required String displayName,
  }) async =>
      testUser(role: role).copyWith(displayName: displayName, email: email);
  @override
  Future<UserModel> loginAsGuest() async => testUser(guest: true);
  @override
  Future<void> logout() async {}
}

Future<AuthProvider> authenticatedProvider({
  UserRole role = UserRole.user,
}) async {
  final provider = AuthProvider(
    authService: FakeAuthService(restoredUser: testUser(role: role)),
  );
  await provider.initialize();
  return provider;
}
