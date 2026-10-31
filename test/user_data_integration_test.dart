import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/recognition/live_camera_screen.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/user/user_data_service.dart';
import 'package:sign_voice/services/staff/staff_service.dart';

import 'auth_fixtures.dart';

http.Response ok(dynamic data, {Map<String, dynamic>? pagination}) =>
    http.Response(
      jsonEncode({'success': true, 'data': data, 'pagination': ?pagination}),
      200,
      headers: {'content-type': 'application/json'},
    );

class UserDataFixture {
  Map<String, dynamic> profile = testUser().toJson();
  Map<String, dynamic> settings = {
    'theme': 'SYSTEM',
    'fontSize': 16,
    'speechSpeed': 1.0,
    'speechPitch': 1.0,
    'avatarColor': 0,
  };
  final List<Map<String, dynamic>> conversations = [];
  final Set<String> favorites = {};
  bool failSave = false;
  late final api = ApiClient(
    client: MockClient(handle),
    tokenStorage: MemoryTokenStore(),
    useRefreshCookie: false,
  );
  late final service = UserDataService(apiClient: api);
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path.endsWith('/users/profile')) {
      if (request.method == 'PATCH') {
        if (failSave) {
          return http.Response(
            jsonEncode({
              'error': {'message': 'Save failed'},
            }),
            500,
          );
        }
        profile = {...profile, ...body};
      }
      return ok(profile);
    }
    if (path.endsWith('/users/settings')) {
      if (request.method == 'PATCH') settings = {...settings, ...body};
      return ok(settings);
    }
    if (path.endsWith('/conversations')) {
      if (request.method == 'POST') {
        final item = {
          '_id': 'a' * 24,
          ...body,
          'favorite': false,
          'createdAt': DateTime(2026).toIso8601String(),
        };
        conversations.add(item);
        return ok(item);
      }
      return ok({
        'items': conversations,
        'total': conversations.length,
        'page': 1,
        'pages': 1,
      });
    }
    if (path.endsWith('/favorites')) {
      if (request.method == 'POST') favorites.add(body['entryId'] as String);
      return ok(
        favorites.map((id) => {'entryId': id}).toList(),
        pagination: {'total': favorites.length},
      );
    }
    return ok({});
  }
}

void main() {
  test('uses real service boundaries and restores profile, preferences, conversations and favorites', () async {
    final fixture = UserDataFixture();
    final a = AppState(service: fixture.service);
    a.bindAccount(testUser().id, asGuest: false);
    expect(await a.synchronize(), isTrue);
    expect(await a.saveProfile({'displayName': 'Saved Name'}), isTrue);
    expect(
      await a.saveSettings({
        'theme': 'DARK',
        'speechSpeed': 1.5,
        'avatarColor': 2,
      }),
      isTrue,
    );
    expect(
      await a.saveConversation(
        'Persisted conversation',
        ConversationDirection.text,
      ),
      isTrue,
    );
    expect(await a.toggleSign('b' * 24), isTrue);
    a.dispose();
    final reloaded = AppState(service: fixture.service);
    reloaded.bindAccount(testUser().id, asGuest: false);
    expect(await reloaded.synchronize(), isTrue);
    expect(reloaded.name, 'Saved Name');
    expect(reloaded.themeMode, ThemeMode.dark);
    expect(reloaded.speechSpeed, 1.5);
    expect(reloaded.avatarColor, 2);
    expect(reloaded.history.single.content, 'Persisted conversation');
    expect(reloaded.favorites, contains('b' * 24));
    reloaded.dispose();
    fixture.api.dispose();
  });
  test(
    'failed saves preserve persisted state and report the server error',
    () async {
      final fixture = UserDataFixture(), state = AppState();
      state.dispose();
      final persisted = AppState(service: fixture.service);
      persisted.bindAccount(testUser().id, asGuest: false);
      await persisted.synchronize();
      fixture.failSave = true;
      expect(
        await persisted.saveProfile({'displayName': 'Unsaved Name'}),
        isFalse,
      );
      expect(persisted.name, 'Test User');
      expect(persisted.error, 'Save failed');
      persisted.dispose();
      fixture.api.dispose();
    },
  );
  test('account changes reset every account-owned setting and selection', () {
    final state = AppState();
    state.bindAccount('first', asGuest: false);
    state.update(() {
      state.transcript = 'private text';
      state.detectedSign = 'private sign';
      state.themeMode = ThemeMode.dark;
      state.avatarColor = 3;
      state.speechSpeed = 2;
      state.selectedSign = const SignEntry(
        'private',
        '',
        '',
        '',
        id: 'private',
      );
    });
    state.bindAccount('second', asGuest: false);
    expect(state.transcript, isEmpty);
    expect(state.detectedSign, isEmpty);
    expect(state.themeMode, ThemeMode.system);
    expect(state.avatarColor, 0);
    expect(state.speechSpeed, 1);
    expect(state.selectedSign.id, isNull);
    state.dispose();
  });
  test('a stale 401 cannot clear the new session or retry a mutation with new credentials', () async {
    final deferred = Completer<http.Response>();
    var requests = 0, invalidations = 0;
    final store = MemoryTokenStore()
      ..accessToken = 'account-a'
      ..refreshToken = 'refresh-a';
    final api = ApiClient(
      client: MockClient((request) async {
        requests++;
        return deferred.future;
      }),
      tokenStorage: store,
      useRefreshCookie: false,
    );
    api.sessionInvalidated.addListener(() => invalidations++);
    final old = api.patch('/users/profile', body: {'displayName': 'Account A'});
    await Future<void>.delayed(Duration.zero);
    final epoch = api.beginAuthentication();
    await api.writeSession(
      epoch,
      () =>
          store.saveTokens(accessToken: 'account-b', refreshToken: 'refresh-b'),
    );
    api.sessionStarted(expectedEpoch: epoch);
    final expectation = expectLater(
      old,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    deferred.complete(
      http.Response(
        jsonEncode({
          'error': {'code': 'AUTH_SESSION_INVALID'},
        }),
        401,
      ),
    );
    await expectation;
    expect(requests, 1);
    expect(invalidations, 0);
    expect(store.accessToken, 'account-b');
    api.dispose();
  });
  test('a late refresh cannot overwrite tokens from a new login', () async {
    final deferred = Completer<http.Response>();
    final store = MemoryTokenStore()
      ..accessToken = 'account-a'
      ..refreshToken = 'refresh-a';
    final api = ApiClient(
      client: MockClient((_) => deferred.future),
      tokenStorage: store,
      useRefreshCookie: false,
    );
    final old = api.refreshToken();
    await Future<void>.delayed(Duration.zero);
    final epoch = api.beginAuthentication();
    await api.writeSession(
      epoch,
      () =>
          store.saveTokens(accessToken: 'account-b', refreshToken: 'refresh-b'),
    );
    api.sessionStarted(expectedEpoch: epoch);
    final expectation = expectLater(
      old,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    deferred.complete(
      ok({'accessToken': 'late-a', 'refreshToken': 'late-refresh-a'}),
    );
    await expectation;
    expect(store.accessToken, 'account-b');
    expect(store.refreshToken, 'refresh-b');
    api.dispose();
  });
  test('staff stats decode the actual flat backend DTO', () async {
    final api = ApiClient(
      client: MockClient(
        (_) async => ok({
          'content': {'pending': 2, 'published': 5},
          'users': {'total': 3, 'recentWeek': 1},
        }),
      ),
      tokenStorage: MemoryTokenStore(),
      useRefreshCookie: false,
    );
    final stats = await StaffService(apiClient: api).getStats();
    expect(stats.content.pending, 2);
    expect(stats.users.total, 3);
    api.dispose();
  });
  testWidgets('profile editor retains the draft when persistence fails', (
    tester,
  ) async {
    final fixture = UserDataFixture()..failSave = true;
    final state = AppState(service: fixture.service);
    final auth = await authenticatedProvider();
    await tester.pumpWidget(
      SignVoiceApp(initialScreen: 'S26', state: state, auth: auth),
    );
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, 'Họ và tên');
    await tester.enterText(name, 'Unsaved draft');
    await tester.ensureVisible(find.text('Lưu thay đổi'));
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(find.text('Save failed'), findsOneWidget);
    expect(find.text('Unsaved draft'), findsOneWidget);
    expect(fixture.profile['displayName'], 'Test User');
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
    auth.dispose();
    fixture.api.dispose();
  });
  testWidgets(
    'webcam settings omit all local diagnostic recording and export controls',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState();
      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(state: state, child: const LiveCameraScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final settings = find.byTooltip('Cài đặt nhận diện');
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(find.text('Cài đặt nhận diện'), findsOneWidget);
      for (final label in [
        'Ghi chẩn đoán cục bộ',
        'Kèm ảnh camera để đối chiếu',
        'Xuất bản ghi JSON',
        'Xóa bản ghi cục bộ',
      ]) {
        expect(find.text(label), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
  testWidgets(
    'shared STAFF dashboard routes to content and retains failed edits',
    (tester) async {
      final auth = await authenticatedProvider(role: UserRole.staff);
      final store = MemoryTokenStore();
      var failed = false;
      final item = {
        '_id': 'c' * 24,
        'word': 'Owned word',
        'definition': 'Owned definition',
        'status': 'DRAFT',
        'categoryId': 'd' * 24,
        'createdBy': testUser().id,
        'videoUrl': 'https://example.org/video.mp4',
        'difficulty': 'BEGINNER',
      };
      final api = ApiClient(
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/admin/stats')) {
            return ok({
              'content': {'total': 1, 'pending': 1, 'published': 0},
            });
          }
          if (path.endsWith('/categories')) {
            return ok([
              {'_id': 'd' * 24, 'name': 'Greeting'},
            ]);
          }
          if (request.method == 'PATCH') {
            failed = true;
            return http.Response(
              jsonEncode({
                'error': {'message': 'Retry save'},
              }),
              500,
            );
          }
          if (path.endsWith('/admin/dictionary')) {
            return ok({
              'items': [item],
              'pagination': {'page': 1, 'pages': 1, 'total': 1},
            });
          }
          return ok({});
        }),
        tokenStorage: store,
        useRefreshCookie: false,
      );
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(
          initialScreen: 'staff',
          auth: auth,
          state: state,
          adminService: AdminWorkspaceService(apiClient: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(ListTile, 'Từ điển').hitTestable(),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(ListTile, 'Từ điển'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Owned word'));
      await tester.tap(find.byTooltip('Thao tác'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Từ / cụm từ'),
        'Draft edit',
      );
      await tester.ensureVisible(find.text('Lưu thay đổi'));
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(failed, isTrue);
      expect(find.text('Retry save'), findsOneWidget);
      expect(find.text('Draft edit'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      auth.dispose();
      api.dispose();
    },
  );
}
