import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/auth/auth_service.dart';

import 'auth_fixtures.dart';

void main() {
  for (final cookie in [false, true]) {
    test(
      'registration stays signed out for cookie=$cookie and only login stores tokens',
      () async {
        final store = MemoryTokenStore();
        final api = ApiClient(
          tokenStorage: store,
          useRefreshCookie: cookie,
          client: MockClient((req) async {
            final body = jsonDecode(req.body) as Map;
            expect(body['email'], 'new@example.com');
            if (req.url.path.endsWith('/register')) {
              expect(body['requireLogin'], true);
              return http.Response(
                jsonEncode({
                  'success': true,
                  'data': {'user': testUser().toJson(), 'loginRequired': true},
                }),
                201,
              );
            }
            expect(req.url.path, endsWith('/login'));
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'user': testUser().toJson(),
                  'tokens': {
                    'accessToken': 'access',
                    'refreshToken': 'refresh',
                  },
                },
              }),
              200,
            );
          }),
        );
        final auth = AuthProvider(
          authService: AuthService(apiClient: api, tokenStorage: store),
        );
        final states = <AuthState>[];
        auth.addListener(() => states.add(auth.state));
        expect(
          await auth.register(
            email: 'new@example.com',
            password: 'Test1234',
            displayName: 'New user',
          ),
          true,
        );
        expect(auth.isAuthenticated, false);
        expect(states, isNot(contains(AuthState.authenticated)));
        expect(store.accessToken, isNull);
        expect(store.refreshToken, isNull);
        expect(
          await auth.login(email: 'new@example.com', password: 'Test1234'),
          true,
        );
        expect(auth.isAuthenticated, true);
        expect(store.accessToken, 'access');
        auth.dispose();
        api.dispose();
      },
    );
  }

  testWidgets(
    'registration returns to login, retains email and clears passwords',
    (tester) async {
      final auth = AuthProvider(authService: FakeAuthService());
      await auth.initialize();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: MaterialApp(
            home: const AuthScreen(register: true),
            routes: {
              'S08': (_) => const Scaffold(body: Text('Protected home')),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tiếp tục với Google'), findsNothing);
      await tester.enterText(find.byType(TextFormField).at(0), 'New user');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'new@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'Test1234');
      await tester.enterText(find.byType(TextFormField).at(3), 'Test1234');
      final submit = find.byKey(const ValueKey('auth-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(auth.isAuthenticated, false);
      expect(find.text('Protected home'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'new@example.com',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextFormField).last, 'Test1234');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(auth.isAuthenticated, true);
      expect(find.text('Protected home'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
}
