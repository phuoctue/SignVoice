import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';

import 'auth_fixtures.dart';

class PasswordAuth extends FakeAuthService {
  PasswordAuth(UserRole role) : super(restoredUser: testUser(role: role));
  int calls = 0;
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    calls++;
    if (currentPassword != 'CurrentPassword123') {
      throw ApiException(message: 'Mật khẩu hiện tại không đúng.');
    }
  }
}

class PasswordAdminService extends AdminWorkspaceService {
  int calls = 0;
  bool fail = true;
  String? target;
  @override
  Future<AdminPageData> list(
    String resource, {
    int page = 1,
    String search = '',
    String? status,
    String? role,
  }) async => const AdminPageData(
    [
      {
        '_id': '0123456789abcdef01234568',
        'email': 'target@example.com',
        'displayName': 'Target',
        'accountType': 'LOCAL',
        'status': 'ACTIVE',
        'role': 'USER',
        'isGuest': false,
      },
    ],
    1,
    1,
    1,
  );
  @override
  Future<List<AdminRecord>> roles() async => [];
  @override
  Future<void> resetUserPassword(String id, String newPassword) async {
    calls++;
    target = id;
    if (fail) {
      throw ApiException(message: 'Chưa lưu được mật khẩu. Hãy thử lại.');
    }
  }
}

void main() {
  testWidgets(
    'admin reset validates confirmation, preserves failed input and keeps admin signed in',
    (tester) async {
      final auth = await authenticatedProvider(role: UserRole.admin);
      addTearDown(auth.dispose);
      final service = PasswordAdminService();
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          state: AppState(),
          adminService: service,
          initialScreen: '/admin/users',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thao tác'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đặt lại mật khẩu'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'weak');
      await tester.enterText(fields.at(1), 'weak');
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      await tester.enterText(fields.at(0), 'NewPassword123');
      await tester.enterText(fields.at(1), 'different');
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      await tester.enterText(fields.at(1), 'NewPassword123');
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa lưu được mật khẩu. Hãy thử lại.'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'NewPassword123',
      );
      service.fail = false;
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(service.calls, 2);
      expect(service.target, '0123456789abcdef01234568');
      expect(auth.isAuthenticated, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'admin reset dialog clears on logout without changing a target password',
    (tester) async {
      final auth = await authenticatedProvider(role: UserRole.admin);
      addTearDown(auth.dispose);
      final service = PasswordAdminService();
      await tester.pumpWidget(
        SignVoiceApp(
          auth: auth,
          state: AppState(),
          adminService: service,
          initialScreen: '/admin/users',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thao tác'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đặt lại mật khẩu'));
      await tester.pumpAndSettle();
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(service.calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final role in UserRole.values) {
    testWidgets('profile password form validates and permits retry for $role', (
      tester,
    ) async {
      final service = PasswordAuth(role);
      final auth = AuthProvider(authService: service);
      await auth.initialize();
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        SignVoiceApp(auth: auth, state: AppState(), initialScreen: 'S25'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đổi mật khẩu'), findsNothing);
      await tester.ensureVisible(find.text('Chỉnh sửa hồ sơ'));
      await tester.tap(find.text('Chỉnh sửa hồ sơ'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Đổi mật khẩu'));
      await tester.tap(find.text('Đổi mật khẩu'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(3));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: fields.at(0),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .hintText,
        'Nhập mật khẩu đang dùng',
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: fields.at(2),
                matching: find.byType(TextField),
              ),
            )
            .decoration!
            .hintText,
        'Nhập lại chính xác mật khẩu mới',
      );
      await tester.enterText(fields.at(0), 'wrong');
      await tester.enterText(fields.at(1), 'NewPassword123');
      await tester.enterText(fields.at(2), 'different');
      await tester.ensureVisible(find.text('Lưu mật khẩu mới'));
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      expect(find.text('Mật khẩu nhập lại chưa khớp.'), findsOneWidget);
      await tester.enterText(fields.at(2), 'NewPassword123');
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(find.text('Mật khẩu hiện tại không đúng.'), findsOneWidget);
      expect(auth.isAuthenticated, isTrue);
      await tester.enterText(fields.at(0), 'CurrentPassword123');
      await tester.ensureVisible(find.text('Lưu mật khẩu mới'));
      await tester.tap(find.text('Lưu mật khẩu mới'));
      await tester.pumpAndSettle();
      expect(service.calls, 2);
      expect(auth.isAuthenticated, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
