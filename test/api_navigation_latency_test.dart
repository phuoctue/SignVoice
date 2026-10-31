import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';

import 'auth_fixtures.dart';

class PendingRights extends FakeAuthService {
  PendingRights() : super(restoredUser: testUser(role: UserRole.admin));
  final result = Completer<UserModel>();
  @override
  Future<UserModel> getCurrentUser() => result.future;
}

class PendingAdminData extends DemoDictionaryService {
  final statistics = Completer<AdminRecord>();
  final labels = Completer<List<AdminRecord>>();
  int statsCalls = 0, labelCalls = 0;
  @override
  Future<AdminRecord> stats() {
    statsCalls++;
    return statistics.future;
  }

  @override
  Future<List<AdminRecord>> roles() {
    labelCalls++;
    return labels.future;
  }

  @override
  Future<AdminPageData> list(
    String resource, {
    int page = 1,
    String search = '',
    String? status,
    String? role,
  }) async => AdminPageData(
    [
      {
        '_id': '1' * 24,
        'displayName': 'Visible account',
        'email': 'owner@example.com',
        'role': 'USER',
        'customRoleId': '2' * 24,
        'status': 'ACTIVE',
      },
    ],
    1,
    1,
    1,
  );
}

void main() {
  testWidgets(
    'dashboard requests stats before role refresh finishes without exposing revoked modules',
    (tester) async {
      final service = PendingAdminData(), rights = PendingRights();
      final auth = AuthProvider(authService: rights), state = AppState();
      addTearDown(auth.dispose);
      addTearDown(state.dispose);
      await auth.initialize();
      await tester.pumpWidget(
        SignVoiceApp(
          initialScreen: 'admin',
          auth: auth,
          state: state,
          adminService: service,
        ),
      );
      await tester.pump();
      expect(service.statsCalls, 1);
      service.statistics.complete({
        'users': {'total': 999},
        'sessions': {'active': 99},
        'content': {'total': 3, 'published': 2, 'pending': 1},
      });
      await tester.pump();
      expect(find.text('Mục từ điển'), findsNothing);
      rights.result.complete(testUser(role: UserRole.staff));
      await tester.pumpAndSettle();
      expect(find.text('Mục từ điển'), findsOneWidget);
      expect(find.text('999'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Tài khoản'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('account rows appear without waiting for auxiliary role names', (
    tester,
  ) async {
    final service = PendingAdminData(),
        auth = await authenticatedProvider(role: UserRole.admin),
        state = AppState();
    addTearDown(auth.dispose);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        initialScreen: '/admin/users',
        auth: auth,
        state: state,
        adminService: service,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(service.labelCalls, 1);
    expect(find.text('Visible account'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('1 mục'), findsOneWidget);
    service.labels.complete([
      {'_id': '2' * 24, 'name': 'Custom display label'},
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Custom display label'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
