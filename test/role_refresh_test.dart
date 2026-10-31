import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/screens/admin/admin_dashboard_screen.dart';

import 'auth_fixtures.dart';

class ChangingRoleService extends FakeAuthService {
  ChangingRoleService() : super(restoredUser: testUser());
  UserModel current = testUser();
  final pending = <Completer<UserModel>>[];
  int reads = 0;
  @override
  Future<UserModel> getCurrentUser() async {
    reads++;
    return pending.isEmpty ? current : pending.removeAt(0).future;
  }
}

void main() {
  test(
    'role refresh preserves profile edits acknowledged during the request',
    () async {
      final service = ChangingRoleService();
      final auth = AuthProvider(authService: service);
      addTearDown(auth.dispose);
      await auth.initialize();
      final result = Completer<UserModel>();
      service.pending.add(result);
      final refresh = auth.refreshUser();
      auth.applyAcknowledgedProfile(
        userId: auth.user!.id,
        displayName: 'Updated profile',
        email: 'updated@example.com',
        avatarUrl: '/new-avatar.png',
      );
      result.complete(testUser(role: UserRole.staff));
      await refresh;
      expect(auth.user!.displayName, 'Updated profile');
      expect(auth.user!.avatarUrl, '/new-avatar.png');
      expect(auth.user!.email, 'updated@example.com');
      expect(auth.isStaff, isTrue);
    },
  );
  test(
    'role refresh shares one request and applies promotion and demotion',
    () async {
      final service = ChangingRoleService();
      final auth = AuthProvider(authService: service);
      addTearDown(auth.dispose);
      await auth.initialize();
      final result = Completer<UserModel>();
      service.pending.add(result);
      final first = auth.refreshUser(), second = auth.refreshUser();
      expect(identical(first, second), isTrue);
      expect(service.reads, 1);
      result.complete(testUser(role: UserRole.staff));
      await Future.wait([first, second]);
      expect(auth.isStaff, isTrue);
      expect(auth.isAdmin, isFalse);
      expect(auth.can('users:write'), isFalse);
      await auth.refreshUser();
      expect(auth.isStaff, isFalse);
    },
  );

  test(
    'an old session response cannot grant roles after a new login',
    () async {
      final service = ChangingRoleService();
      final auth = AuthProvider(authService: service);
      addTearDown(auth.dispose);
      await auth.initialize();
      final oldResult = Completer<UserModel>();
      service.pending.add(oldResult);
      final oldRequest = auth.refreshUser();
      await auth.logout();
      await auth.login(email: 'user@example.com', password: 'Test1234');
      await auth.refreshUser();
      expect(service.reads, 2);
      oldResult.complete(testUser(role: UserRole.admin));
      await oldRequest;
      expect(auth.user!.role, UserRole.user);
      expect(auth.isAdmin, isFalse);
    },
  );

  testWidgets(
    'opening profile exposes staff role and resume removes revoked access',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = ChangingRoleService()
        ..current = testUser(role: UserRole.staff);
      final auth = AuthProvider(authService: service);
      final state = AppState();
      addTearDown(auth.dispose);
      addTearDown(state.dispose);
      await auth.initialize();
      await tester.pumpWidget(
        SignVoiceApp(
          initialScreen: 'S25',
          auth: auth,
          state: state,
          adminService: RoleDashboardService(),
          learningService: DemoLearningService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nhân viên · STAFF'), findsOneWidget);
      expect(
        find.widgetWithText(NavigationDestination, 'Nhân viên'),
        findsNothing,
      );
      expect(
        find.widgetWithText(NavigationDestination, 'Quản trị'),
        findsOneWidget,
      );
      expect(find.text('Quản lý nội dung'), findsNothing);
      expect(service.reads, 1);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Quản trị'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(find.text('Role & phân quyền'), findsNothing);
      expect(find.text('Tài khoản'), findsNothing);
      expect(find.text('Phiên đăng nhập'), findsNothing);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Cá nhân'));
      await tester.pumpAndSettle();
      expect(find.text('Nhân viên · STAFF'), findsOneWidget);
      final readsBeforeResume = service.reads;

      service.current = testUser();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Người dùng · USER'), findsOneWidget);
      expect(
        find.widgetWithText(NavigationDestination, 'Quản trị'),
        findsNothing,
      );
      expect(find.text('Quản lý nội dung'), findsNothing);
      expect(service.reads, readsBeforeResume + 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class RoleDashboardService extends DemoDictionaryService {
  @override
  Future<AdminRecord> stats() async => {
    'content': {'total': 1, 'published': 1, 'pending': 0},
  };
}
