import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/screens/admin/admin_dashboard_screen.dart';
import 'package:sign_voice/screens/admin/admin_management_screens.dart';
import 'package:sign_voice/screens/admin/admin_ui.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/services/api/api_client.dart';

import 'auth_fixtures.dart';

AdminWorkspaceService serviceFor(
  Future<http.Response> Function(http.Request) handler,
) => AdminWorkspaceService(
  apiClient: ApiClient(
    client: MockClient(handler),
    tokenStorage: MemoryTokenStore(),
    useRefreshCookie: false,
  ),
);
http.Response response(dynamic data, {int code = 200}) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  code,
  headers: {'content-type': 'application/json'},
);
const role = {
  '_id': 'abcabcabcabcabcabcabcabc',
  'name': 'Biên tập viên',
  'key': 'EDITOR',
  'permissions': ['admin:access', 'dictionary:read'],
  'system': false,
};
Future<http.Response> basicHandler(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/stats')) {
    return response({
      'users': {'total': 3},
      'content': {'total': 4, 'published': 2, 'pending': 2},
      'sessions': {'active': 1},
    });
  }
  if (path.endsWith('/roles') || path.endsWith('/role-options')) {
    return response([role]);
  }
  if (path.endsWith('/categories')) {
    return response([
      {
        '_id': '123123123123123123123123',
        'name': 'Chào hỏi',
        'slug': 'chao-hoi',
        'status': 'ACTIVE',
        'wordCount': 1,
      },
    ]);
  }
  final key = path.endsWith('/users')
      ? 'users'
      : path.endsWith('/sessions')
      ? 'sessions'
      : 'items';
  return response({
    key: [],
    'pagination': {'page': 1, 'pages': 1, 'total': 0},
  });
}

Future<void> pumpApp(
  WidgetTester tester, {
  String screen = 'S25',
  UserModel? user,
  AdminWorkspaceService? service,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = AuthProvider(
    authService: FakeAuthService(
      restoredUser: user ?? testUser(role: UserRole.admin),
    ),
  );
  await auth.initialize();
  addTearDown(auth.dispose);
  await tester.pumpWidget(
    SignVoiceApp(
      initialScreen: screen,
      state: AppState(),
      auth: auth,
      adminService: service ?? serviceFor(basicHandler),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final role in [UserRole.admin, UserRole.staff]) {
    testWidgets('$role personal page stays compact on desktop', (tester) async {
      await pumpApp(tester, user: testUser(role: role));
      tester.view.physicalSize = const Size(1600, 1000);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(Scaffold)).width,
        lessThanOrEqualTo(480),
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
  testWidgets('management and personal pages share phone layout on desktop', (
    tester,
  ) async {
    await pumpApp(tester, screen: 'admin');
    tester.view.physicalSize = const Size(1600, 1000);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)).width, lessThanOrEqualTo(480));
    await tester.tap(find.text('Cá nhân'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)).width, lessThanOrEqualTo(480));
    await tester.tap(find.text('Quản trị'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)).width, lessThanOrEqualTo(480));
    await tester.scrollUntilVisible(
      find.text('Danh mục'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(AdminDashboardScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Danh mục')),
      alignment: .4,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Danh mục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm mới'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)).width, lessThanOrEqualTo(480));
    Navigator.pop(tester.element(find.byType(Scaffold)));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)).width, lessThanOrEqualTo(480));
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Scaffold)).width, 390);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  test('custom role permissions do not inherit the coarse ADMIN alias', () {
    final user = testUser(role: UserRole.admin).copyWith(
      customRoleId: 'role-id',
      permissions: ['admin:access', 'dictionary:read'],
    );
    expect(user.isAdmin, isTrue);
    expect(user.hasPermission('users:write'), isFalse);
    final restored = UserModel.fromJson(user.toJson());
    expect(restored.customRoleId, 'role-id');
    expect(restored.permissions, user.permissions);
  });
  test(
    'service parses arrays and pagination and sends correct CRUD requests',
    () async {
      final requests = <http.Request>[];
      final service = serviceFor((request) async {
        requests.add(request);
        return basicHandler(request);
      });
      expect((await service.list('roles')).items.single['key'], 'EDITOR');
      expect((await service.list('users', page: 2, search: 'email')).total, 0);
      await service.save('roles', {'name': 'Role'}, id: 'abc');
      await service.delete('roles', 'abc');
      expect(requests[1].url.queryParameters['page'], '2');
      expect(requests[1].url.queryParameters['search'], 'email');
      expect(requests[2].method, 'PATCH');
      expect(jsonDecode(requests[2].body), {'name': 'Role'});
      expect(requests[3].method, 'DELETE');
    },
  );
  testWidgets(
    'admin personal tab has no management cards and opens fifth tab dashboard',
    (tester) async {
      await pumpApp(tester);
      expect(find.text('Quản trị hệ thống'), findsNothing);
      expect(find.text('Quản lý nội dung'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await tester.tap(find.text('Quản trị'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(find.text('Tổng quan'), findsOneWidget);
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, 4);
    },
  );
  testWidgets('USER has four tabs and cannot open management deep links', (
    tester,
  ) async {
    await pumpApp(tester, user: testUser());
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('Quản trị'), findsNothing);
    for (final path in [
      '/admin/roles',
      '/admin/users',
      '/admin/dictionary',
      '/admin/categories',
      '/admin/sessions',
      '/admin/content',
    ]) {
      final context = tester.element(find.byType(NavigationBar));
      Navigator.pushNamed(context, path);
      await tester.pumpAndSettle();
      expect(
        find.text('Bạn không có quyền truy cập trang này.'),
        findsOneWidget,
      );
      Navigator.pop(tester.element(find.byType(Scaffold).last));
      await tester.pumpAndSettle();
    }
  });
  testWidgets(
    'STAFF shares admin dashboard with content tools and blocks sensitive deep links',
    (tester) async {
      await pumpApp(
        tester,
        screen: 'admin',
        user: testUser(role: UserRole.staff),
      );
      expect(find.byType(AdminDashboardScreen), findsOneWidget);
      expect(
        find.widgetWithText(NavigationDestination, 'Quản trị'),
        findsOneWidget,
      );
      for (final label in [
        'Tài khoản',
        'Role & phân quyền',
        'Phiên đăng nhập',
      ]) {
        expect(find.widgetWithText(ListTile, label), findsNothing);
      }
      for (final label in [
        'Từ điển',
        'Danh mục',
        'Bộ sưu tập công khai',
        'Duyệt nội dung',
      ]) {
        if (find.widgetWithText(ListTile, label).evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            find.widgetWithText(ListTile, label),
            180,
            scrollable: find.byType(Scrollable).first,
          );
        }
        expect(find.widgetWithText(ListTile, label), findsOneWidget);
      }
      for (final path in [
        '/admin/users',
        '/admin/roles',
        '/admin/sessions',
        '/staff/users',
      ]) {
        Navigator.pushNamed(tester.element(find.byType(NavigationBar)), path);
        await tester.pumpAndSettle();
        expect(
          find.text('Bạn không có quyền truy cập trang này.'),
          findsOneWidget,
        );
        Navigator.pop(tester.element(find.byType(Scaffold).last));
        await tester.pumpAndSettle();
      }
      for (final path in [
        '/admin/dictionary',
        '/admin/categories',
        '/admin/content',
      ]) {
        Navigator.pushNamed(tester.element(find.byType(NavigationBar)), path);
        await tester.pumpAndSettle();
        expect(find.byType(AdminResourceScreen), findsOneWidget);
        expect(
          find.text('Bạn không có quyền truy cập trang này.'),
          findsNothing,
        );
        Navigator.pop(tester.element(find.byType(Scaffold).last));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'limited custom role sees dictionary only and cannot access users',
    (tester) async {
      await pumpApp(
        tester,
        screen: 'admin',
        user: testUser(role: UserRole.admin).copyWith(
          customRoleId: 'role-id',
          permissions: ['admin:access', 'dictionary:read'],
        ),
      );
      expect(find.text('Role & phân quyền'), findsNothing);
      expect(find.text('Tài khoản'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Từ điển'), findsOneWidget);
      Navigator.pushNamed(
        tester.element(find.byType(NavigationBar)),
        '/admin/users',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Bạn không có quyền truy cập trang này.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'creates a custom role with selected permissions and reloads list',
    (tester) async {
      AdminRecord? submitted;
      final service = serviceFor((request) async {
        if (request.method == 'POST') {
          submitted = Map<String, dynamic>.from(jsonDecode(request.body));
          return response(role, code: 201);
        }
        return basicHandler(request);
      });
      await pumpApp(tester, screen: '/admin/roles', service: service);
      await tester.tap(find.text('Thêm mới'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminEditorScreen), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên role'),
        'Biên tập',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mã role'),
        'editor',
      );
      await tester.ensureVisible(
        find.text(adminPermissionLabels['admin:access']!),
      );
      await tester.tap(find.text(adminPermissionLabels['admin:access']!));
      await tester.pump();
      await tester.ensureVisible(find.text('Từ điển và xuất bản'));
      await tester.tap(find.text('Từ điển và xuất bản'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Xem toàn bộ từ điển'));
      await tester.tap(find.text('Xem toàn bộ từ điển'));
      await tester.pump();
      await tester.ensureVisible(find.text('Lưu thay đổi'));
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(submitted!['key'], 'EDITOR');
      expect(
        submitted!['permissions'],
        containsAll(['admin:access', 'dictionary:read']),
      );
      expect(find.byType(AdminResourceScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('save failure keeps entered values and displays server error', (
    tester,
  ) async {
    final service = serviceFor(
      (request) async => request.method == 'POST'
          ? http.Response(
              jsonEncode({
                'success': false,
                'error': {'message': 'Role đã tồn tại', 'code': 'CONFLICT'},
              }),
              409,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )
          : basicHandler(request),
    );
    await pumpApp(tester, screen: '/admin/categories', service: service);
    await tester.tap(find.text('Thêm mới'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên danh mục'),
      'Chào hỏi',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Slug'),
      'chao-hoi',
    );
    await tester.ensureVisible(find.text('Lưu thay đổi'));
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(find.text('Role đã tồn tại'), findsOneWidget);
    expect(find.byType(AdminEditorScreen), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Slug'))
          .controller!
          .text,
      'chao-hoi',
    );
  });
  testWidgets(
    'deletes a role only after confirmation and keeps list on rejected delete',
    (tester) async {
      int deletes = 0;
      final service = serviceFor((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          return http.Response(
            jsonEncode({
              'success': false,
              'error': {
                'message': 'Role đang được gán cho tài khoản',
                'code': 'CONFLICT',
              },
            }),
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return basicHandler(request);
      });
      await pumpApp(tester, screen: '/admin/roles', service: service);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(find.text('Role đang được gán cho tài khoản'), findsOneWidget);
      expect(find.text('Biên tập viên'), findsOneWidget);
    },
  );
  for (final resource in ['users', 'dictionary', 'categories', 'sessions']) {
    testWidgets('$resource page loads on mobile with real response shapes', (
      tester,
    ) async {
      await pumpApp(tester, screen: '/admin/$resource');
      expect(find.byType(AdminResourceScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (resource != 'sessions') {
        await tester.tap(find.text('Thêm mới'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('creates a user and assigns a custom role id', (tester) async {
    AdminRecord? saved;
    final service = serviceFor((request) async {
      if (request.method == 'POST') {
        saved = Map<String, dynamic>.from(jsonDecode(request.body));
        return response({}, code: 201);
      }
      return basicHandler(request);
    });
    await pumpApp(tester, screen: '/admin/users', service: service);
    await tester.tap(find.text('Thêm mới'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên hiển thị'),
      'Nhân viên',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'editor@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mật khẩu ban đầu'),
      'Editor123!',
    );
    await Scrollable.ensureVisible(
      tester.element(find.byType(AdminSelectField)),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AdminSelectField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biên tập viên').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lưu thay đổi'));
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(saved!['customRoleId'], role['_id']);
    expect(saved!['role'], isNull);
    expect(saved!['email'], 'editor@example.com');
  });
  testWidgets(
    'creates and publishes dictionary content with selected category',
    (tester) async {
      AdminRecord? saved;
      final service = serviceFor((request) async {
        if (request.method == 'POST') {
          saved = Map<String, dynamic>.from(jsonDecode(request.body));
          return response({}, code: 201);
        }
        return basicHandler(request);
      });
      await pumpApp(tester, screen: '/admin/dictionary', service: service);
      await tester.tap(find.text('Thêm mới'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Từ / cụm từ'),
        'Xin chào',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Định nghĩa'),
        'Dùng để chào hỏi.',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'URL video ký hiệu'),
        'https://example.com/sign.mp4',
      );
      await tester.ensureVisible(
        find.widgetWithText(AdminSelectField, 'Trạng thái'),
      );
      await tester.tap(find.widgetWithText(AdminSelectField, 'Trạng thái'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đã xuất bản').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Lưu thay đổi'));
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(saved!['status'], 'PUBLISHED');
      expect(saved!['categoryId'], '123123123123123123123123');
      expect(saved!['word'], 'Xin chào');
    },
  );
  testWidgets('shows session user agent and revokes after confirmation', (
    tester,
  ) async {
    bool revoked = false;
    final service = serviceFor((request) async {
      if (request.method == 'DELETE') {
        revoked = true;
        return response({});
      }
      if (request.url.path.endsWith('/sessions')) {
        return response({
          'sessions': revoked
              ? []
              : [
                  {
                    '_id': '123123123123123123123123',
                    'userId': {
                      'displayName': 'Editor',
                      'email': 'editor@example.com',
                    },
                    'sessionType': 'REFRESH',
                    'deviceInfo': 'Chrome Windows',
                  },
                ],
          'pagination': {'page': 1, 'pages': 1, 'total': revoked ? 0 : 1},
        });
      }
      return basicHandler(request);
    });
    await pumpApp(tester, screen: '/admin/sessions', service: service);
    expect(find.textContaining('Chrome Windows'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thu hồi phiên'));
    await tester.pumpAndSettle();
    expect(revoked, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, 'Thu hồi'));
    await tester.pumpAndSettle();
    expect(revoked, isTrue);
    expect(find.text('Chưa có dữ liệu.'), findsOneWidget);
  });
}
