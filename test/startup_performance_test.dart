import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/features/home/home_screen.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/user/user_data_service.dart';

import 'user_data_integration_test.dart' show UserDataFixture;

import 'auth_fixtures.dart';

class PendingRestore extends FakeAuthService {
  final pending = Completer<UserModel?>();
  @override
  Future<UserModel?> restoreSession() => pending.future;
}

class CountingHistory extends UserDataFixture {
  int historyRequests = 0;
  @override
  Future<http.Response> handle(http.Request request) {
    if (request.url.path.endsWith('/conversations')) historyRequests++;
    return super.handle(request);
  }
}

void main() {
  testWidgets('ready sessions leave splash without a fixed branding delay', (
    tester,
  ) async {
    final auth = await authenticatedProvider();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: AppState(),
        adminService: DemoDictionaryService(),
        learningService: DemoLearningService(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
  });
  testWidgets('home does not refetch history just restored during startup', (
    tester,
  ) async {
    final fixture = CountingHistory(), auth = await authenticatedProvider();
    final state = AppState(service: fixture.service);
    addTearDown(auth.dispose);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: state,
        adminService: DemoDictionaryService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(fixture.historyRequests, 1);
    await state.loadHistory(search: 'old filter');
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    navigator.pushNamedAndRemoveUntil('S08', (_) => false);
    await tester.pumpAndSettle();
    expect(state.historySearch, '');
    expect(fixture.historyRequests, 3);
  });
  testWidgets(
    'pending restore remains on splash until authentication finishes',
    (tester) async {
      final service = PendingRestore(), state = AppState();
      final auth = AuthProvider(authService: service);
      addTearDown(auth.dispose);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          state: state,
          adminService: DemoDictionaryService(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      service.pending.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
    },
  );
  test(
    'production startup loads account data through one authenticated request',
    () async {
      final paths = <String>[];
      final service = StartupUserDataService(
        apiClient: ApiClient(
          tokenStorage: MemoryTokenStore(),
          useRefreshCookie: false,
          client: MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'profile': testUser().toJson(),
                  'settings': {'theme': 'DARK'},
                  'conversations': {
                    'items': [],
                    'page': 1,
                    'pages': 0,
                    'total': 0,
                  },
                  'favorites': [],
                },
              }),
              200,
            );
          }),
        ),
      );
      final data = await service.bootstrap();
      expect(paths, ['/api/v1/users/bootstrap']);
      expect(data.settings['theme'], 'DARK');
      expect(data.profile['id'] ?? data.profile['_id'], testUser().id);
    },
  );
  test(
    'startup falls back for old backends and preserves server errors',
    () async {
      final paths = <String>[];
      var failure = 404;
      final service = StartupUserDataService(
        apiClient: ApiClient(
          tokenStorage: MemoryTokenStore(),
          useRefreshCookie: false,
          client: MockClient((request) async {
            final path = request.url.path;
            paths.add(path);
            if (path.endsWith('/bootstrap')) {
              return http.Response('{}', failure);
            }
            final dynamic data = path.endsWith('/favorites')
                ? []
                : path.endsWith('/conversations')
                ? {'items': [], 'pages': 0, 'page': 1}
                : path.endsWith('/profile')
                ? testUser().toJson()
                : {'theme': 'LIGHT'};
            return http.Response(
              jsonEncode({
                'success': true,
                'data': data,
                'pagination': {'total': 0},
              }),
              200,
            );
          }),
        ),
      );
      expect((await service.bootstrap()).settings['theme'], 'LIGHT');
      expect(
        paths,
        containsAll([
          '/api/v1/users/profile',
          '/api/v1/users/settings',
          '/api/v1/conversations',
          '/api/v1/favorites',
        ]),
      );
      paths.clear();
      failure = 503;
      await expectLater(service.bootstrap(), throwsA(isA<ApiException>()));
      expect(paths, ['/api/v1/users/bootstrap']);
    },
  );
}
