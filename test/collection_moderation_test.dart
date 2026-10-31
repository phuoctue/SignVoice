import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/screens/admin/collection_moderation_screen.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/learning/learning_service.dart';

import 'auth_fixtures.dart';
import 'sign_collections_test.dart' show CollectionsFixture;

class ModerationFixture extends AdminWorkspaceService {
  static const id = CollectionsFixture.id;
  final calls = <String>[];
  final row = <String, dynamic>{
    '_id': id,
    'name': 'Giao tiếp hằng ngày',
    'description': 'Bản công khai để đối chiếu.',
    'wordCount': 1,
    'openReports': 1,
    'moderationState': 'CLEAR',
    'moderationReason': '',
    'moderationVersion': 1,
    'discoveryRequested': true,
    'sharingEnabled': true,
    'capturedAt': '2026-10-29T01:00:00Z',
  };
  final report = <String, dynamic>{
    '_id': 'cccccccccccccccccccccccc',
    'category': 'SPAM',
    'details': 'Nội dung báo cáo cần kiểm tra.',
    'status': 'OPEN',
    'createdAt': '2026-10-29T01:01:00Z',
  };
  final history = <AdminRecord>[];
  bool failWrite = false;
  int writes = 0;
  Completer<void>? gate;
  @override
  Future<AdminRecord> stats() async => {
    'users': {'total': 1},
    'content': {'total': 1, 'published': 1, 'pending': 0},
    'sessions': {'active': 1},
  };
  @override
  Future<AdminRecord> collectionModerationRead(
    String suffix, {
    int page = 1,
    String search = '',
    String? status,
  }) async {
    calls.add('$suffix|$page|$search|$status');
    final items = suffix.isEmpty
        ? ('${row['name']}'.contains(search)
              ? [Map<String, dynamic>.from(row)]
              : <AdminRecord>[])
        : suffix.endsWith('/reports')
        ? (status == 'ALL' || report['status'] == status
              ? [Map<String, dynamic>.from(report)]
              : <AdminRecord>[])
        : suffix.endsWith('/history')
        ? history
        : [
            {
              '_id': CollectionsFixture.entry,
              'word': 'xin chào',
              'definition': 'Nghĩa của ký hiệu đã duyệt.',
              'imageUrls': <String>[],
              'videoUrl': '',
            },
          ];
    return {
      'items': items,
      'pagination': {'page': page, 'pages': 1, 'total': items.length},
      if (suffix == '/$id') 'collection': Map<String, dynamic>.from(row),
    };
  }

  @override
  Future<void> moderateCollection(
    String id,
    String state,
    String reason,
    int version,
  ) async {
    writes++;
    await gate?.future;
    if (failWrite) throw ApiException(message: 'Chưa lưu được kiểm duyệt');
    row['moderationState'] = state;
    row['moderationReason'] = reason;
    row['moderationVersion'] = (row['moderationVersion'] as int) + 1;
    history.add({
      '_id': 'h1',
      'action': 'COLLECTION_MODERATION',
      'actorName': 'Nhân viên A',
      'actorRole': 'STAFF',
      'from': 'CLEAR',
      'to': state,
      'reason': reason,
      'createdAt': '2026-10-29T01:05:00Z',
    });
  }

  @override
  Future<void> resolveCollectionReport(
    String id,
    String reportId,
    String status,
    String reason,
  ) async {
    writes++;
    if (failWrite) throw ApiException(message: 'Chưa lưu được kiểm duyệt');
    report['status'] = status;
    report['resolution'] = reason;
    history.add({
      '_id': 'h2',
      'action': 'COLLECTION_REPORT_RESOLVE',
      'actorName': 'Nhân viên A',
      'actorRole': 'STAFF',
      'to': status,
      'reason': reason,
      'createdAt': '2026-10-29T01:05:00Z',
    });
  }
}

class ModerationLearningFixture extends CollectionsFixture {
  int reports = 0, reviews = 0;
  @override
  Future<LearningRecord> reportSharedCollection(
    String code,
    String category,
    String details,
  ) async {
    reports++;
    if (failWrite) throw ApiException(message: 'Chưa gửi được báo cáo');
    return {'received': true};
  }

  @override
  Future<LearningRecord> requestCollectionReview(String id) async {
    reviews++;
    collections.first['reviewRequestedAt'] = '2026-10-29T01:05:00Z';
    return {'requested': true};
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester, {
    String route = '/admin/collections',
    UserRole role = UserRole.staff,
    UserModel? user,
    ModerationFixture? service,
    ModerationLearningFixture? learning,
    Size size = const Size(390, 844),
    bool dark = false,
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final auth = AuthProvider(
      authService: FakeAuthService(restoredUser: user ?? testUser(role: role)),
    );
    await auth.initialize();
    addTearDown(auth.dispose);
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SignVoiceApp(
        auth: auth,
        state: state,
        adminService: service ?? ModerationFixture(),
        learningService: learning ?? ModerationLearningFixture(),
        initialScreen: route,
      ),
    );
    await tester.pumpAndSettle();
    state.update(() {
      state.fontScale = scale;
      state.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    });
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final role in [UserRole.admin, UserRole.staff]) {
    testWidgets('$role opens collection moderation from the dashboard', (
      tester,
    ) async {
      final service = ModerationFixture();
      await mount(tester, role: role, route: 'admin', service: service);
      if (role == UserRole.staff) {
        expect(find.text('Role & phân quyền'), findsNothing);
        expect(find.text('Phiên đăng nhập'), findsNothing);
      }
      await tap(tester, find.text('Bộ sưu tập công khai'));
      expect(find.byType(CollectionModerationScreen), findsOneWidget);
      expect(service.calls, isNotEmpty);
      await tap(tester, find.text('Giao tiếp hằng ngày'));
      expect(find.text('Chặn chia sẻ'), findsOneWidget);
    });
  }
  testWidgets(
    'regular accounts cannot enter moderation or send management requests',
    (tester) async {
      final service = ModerationFixture();
      await mount(tester, role: UserRole.user, service: service);
      expect(
        find.text('Bạn không có quyền truy cập trang này.'),
        findsOneWidget,
      );
      expect(service.calls, isEmpty);
    },
  );
  testWidgets('a read-only custom role can inspect but cannot moderate', (
    tester,
  ) async {
    final user = testUser(role: UserRole.staff).copyWith(
      customRoleId: 'eeeeeeeeeeeeeeeeeeeeeeee',
      permissions: ['staff:access', 'collections:read'],
    );
    await mount(
      tester,
      user: user,
      route: '/admin/collections/${ModerationFixture.id}',
    );
    expect(find.text('Chặn chia sẻ'), findsNothing);
    expect(find.text('Ẩn khỏi khám phá'), findsNothing);
    await tap(tester, find.text('Báo cáo'));
    expect(find.text('Nội dung báo cáo cần kiểm tra.'), findsOneWidget);
    expect(find.text('Đánh dấu đã xử lý'), findsNothing);
  });
  testWidgets(
    'search is submitted to the server and reports/history load only when opened',
    (tester) async {
      final service = ModerationFixture();
      await mount(tester, service: service);
      await tester.enterText(find.byType(TextField), 'không có bộ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(service.calls.last, contains('không có bộ'));
      expect(find.text('Không có bộ phù hợp'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Giao tiếp');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Giao tiếp hằng ngày'));
      expect(service.calls.any((call) => call.contains('/reports')), isFalse);
      expect(service.calls.any((call) => call.contains('/history')), isFalse);
      await tap(tester, find.text('Báo cáo'));
      expect(service.calls.last, contains('/reports'));
      await tap(tester, find.text('Lịch sử'));
      expect(service.calls.last, contains('/history'));
    },
  );
  testWidgets(
    'moderation requires a reason, preserves failed input and prevents duplicate saves',
    (tester) async {
      final service = ModerationFixture();
      await mount(
        tester,
        service: service,
        route: '/admin/collections/${ModerationFixture.id}',
      );
      await tap(tester, find.text('Chặn chia sẻ'));
      await tap(tester, find.widgetWithText(FilledButton, 'Chặn chia sẻ'));
      expect(service.writes, 0);
      await tester.enterText(
        find.byType(TextFormField),
        'Đã xác minh nội dung vi phạm',
      );
      service.failWrite = true;
      await tap(tester, find.widgetWithText(FilledButton, 'Chặn chia sẻ'));
      expect(find.text('Chưa lưu được kiểm duyệt'), findsOneWidget);
      expect(find.text('Đã xác minh nội dung vi phạm'), findsOneWidget);
      service.failWrite = false;
      service.gate = Completer<void>();
      final submit = find.widgetWithText(FilledButton, 'Chặn chia sẻ');
      await tester.tap(submit);
      await tester.pump();
      expect(service.writes, 2);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(service.row['moderationState'], 'BLOCKED');
      await tap(tester, find.text('Lịch sử'));
      expect(find.text('Nhân viên A · STAFF'), findsOneWidget);
    },
  );
  testWidgets(
    'resolving a report keeps public state unchanged and refreshes open reports',
    (tester) async {
      final service = ModerationFixture();
      await mount(
        tester,
        service: service,
        route: '/admin/collections/${ModerationFixture.id}',
      );
      await tap(tester, find.text('Báo cáo'));
      await tap(tester, find.text('Đánh dấu đã xử lý'));
      await tester.enterText(
        find.byType(TextFormField),
        'Đã đối chiếu và xử lý báo cáo',
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Lưu kết quả'));
      expect(service.report['status'], 'RESOLVED');
      expect(service.row['moderationState'], 'CLEAR');
      expect(find.text('Chưa có báo cáo phù hợp'), findsOneWidget);
    },
  );
  testWidgets(
    'public preview submits a report only after validation and retains failed input',
    (tester) async {
      final learning = ModerationLearningFixture();
      await mount(
        tester,
        role: UserRole.user,
        learning: learning,
        route: '/collections/shared/${CollectionsFixture.code}',
      );
      await tap(tester, find.byTooltip('Báo cáo bộ sưu tập'));
      await tap(tester, find.text('Gửi báo cáo'));
      expect(learning.reports, 0);
      await tap(tester, find.byType(DropdownButtonFormField<String>));
      await tap(tester, find.text('Quảng cáo, spam').last);
      await tester.enterText(find.byType(TextFormField), 'Cần kiểm tra bộ này');
      learning.failWrite = true;
      await tap(tester, find.text('Gửi báo cáo'));
      expect(find.text('Chưa gửi được báo cáo'), findsOneWidget);
      learning.failWrite = false;
      await tap(tester, find.text('Gửi báo cáo'));
      expect(learning.reports, 2);
      expect(
        find.text('Đã ghi nhận báo cáo. Nhân viên sẽ kiểm tra nội dung.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'owner sees a block reason and can explicitly resubmit without unblocking',
    (tester) async {
      final learning = ModerationLearningFixture();
      learning.collections.first.addAll({
        'moderationState': 'BLOCKED',
        'moderationReason': 'Ảnh cần chỉnh sửa',
      });
      await mount(
        tester,
        role: UserRole.user,
        learning: learning,
        route: '/collections/${CollectionsFixture.id}',
      );
      expect(find.textContaining('Ảnh cần chỉnh sửa'), findsOneWidget);
      await tap(tester, find.text('Gửi lại để kiểm tra'));
      await tap(tester, find.text('Gửi kiểm tra'));
      expect(learning.reviews, 1);
      expect(learning.collections.first['moderationState'], 'BLOCKED');
      expect(find.text('Đã gửi · Chờ kiểm tra'), findsOneWidget);
    },
  );
  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 640),
      const Size(844, 390),
      const Size(800, 1024),
    ]) {
      testWidgets('moderation and reason dialog fit 2x text $size dark=$dark', (
        tester,
      ) async {
        await mount(
          tester,
          route: '/admin/collections/${ModerationFixture.id}',
          size: size,
          dark: dark,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Chặn chia sẻ'));
        tester.view.viewInsets = FakeViewPadding(
          bottom: size.height < 500 ? 160 : 260,
        );
        await tester.enterText(
          find.byType(TextFormField),
          'Nội dung đã được kiểm tra',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Hủy'));
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        await tap(tester, find.text('Báo cáo'));
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('Lịch sử'));
        expect(tester.takeException(), isNull);
      });
      testWidgets(
        'public report dialog fits 2x text and keyboard $size dark=$dark',
        (tester) async {
          await mount(
            tester,
            route: '/collections/shared/${CollectionsFixture.code}',
            role: UserRole.user,
            size: size,
            dark: dark,
            scale: 2,
          );
          await tap(tester, find.byTooltip('Báo cáo bộ sưu tập'));
          tester.view.viewInsets = FakeViewPadding(
            bottom: size.height < 500 ? 160 : 260,
          );
          await tester.enterText(find.byType(TextFormField), 'Mô tả nội dung');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tap(tester, find.text('Gửi báo cáo'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
