import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/home/featured_dictionary.dart';
import 'package:sign_voice/features/notifications/notification_screens.dart';
import 'package:sign_voice/features/profile/profile_screens.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/services/notifications/notification_service.dart';
import 'package:sign_voice/services/user/avatar_picker.dart';

import 'auth_fixtures.dart';
import 'user_data_integration_test.dart' show UserDataFixture, ok;

const png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j7X8AAAAASUVORK5CYII=';

class TestDeviceNotifications extends NotificationService {
  TestDeviceNotifications(super.state) : super(onOpen: (_) {});
  @override
  bool get supported => false;
}

class MediaFixture extends UserDataFixture {
  Map<String, dynamic>? savedProfile;
  int feedCalls = 0;
  bool read = false;
  int profileReads = 0, settingsWrites = 0;
  @override
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/users/profile') && request.method == 'GET') {
      profileReads++;
    }
    if (path.endsWith('/users/settings') && request.method == 'PATCH') {
      settingsWrites++;
    }
    if (path.endsWith('/users/profile') && request.method == 'PATCH') {
      savedProfile = jsonDecode(request.body) as Map<String, dynamic>;
      profile = {
        ...profile,
        ...savedProfile!,
        'avatarUrl': savedProfile!['avatarImage'] != null
            ? '/user-media/avatars/${testUser().id}/${'a' * 64}.png'
            : savedProfile!['avatarUrl'],
      };
      return ok(profile);
    }
    if (path.endsWith('/users/notifications')) {
      if (feedCalls++ == 0) return http.Response('{}', 503);
      return ok({
        'items': [
          {
            '_id': 'notice1',
            'kind': 'REVIEW',
            'title': 'Đến lúc ôn lại',
            'body': 'Bạn có 2 từ cần ôn tập.',
            'route': '/learn?tab=1',
            'read': read,
          },
        ],
      });
    }
    if (path.endsWith('/users/notifications/notice1')) {
      read = true;
      return ok({'read': true});
    }
    return super.handle(request);
  }
}

class FeaturedFixture extends DemoDictionaryService {
  @override
  Future<List<AdminRecord>> featuredEntries() async => [
    {
      '_id': 'real-entry',
      'word': 'Từ trong dữ liệu',
      'thumbnailUrl': 'data:image/png;base64,$png',
    },
  ];
}

void main() {
  Future<(AppState, MediaFixture, AuthProvider, TestDeviceNotifications)> setup(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = MediaFixture(), auth = await authenticatedProvider();
    final state = AppState(service: fixture.service)
      ..bindAccount(testUser().id, asGuest: false);
    await state.synchronize();
    final device = TestDeviceNotifications(state);
    addTearDown(() {
      device.dispose();
      state.dispose();
      auth.dispose();
    });
    return (state, fixture, auth, device);
  }

  Widget host(
    Widget page,
    AppState state,
    AuthProvider auth,
    NotificationService device,
  ) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: device),
      Provider<AdminWorkspaceService>.value(value: FeaturedFixture()),
    ],
    child: AppScope(
      state: state,
      child: MaterialApp(
        home: page,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Text(settings.name!)),
        ),
      ),
    ),
  );

  testWidgets('home renders real featured words and opens the selected entry', (
    tester,
  ) async {
    final (state, _, auth, device) = await setup(tester);
    await tester.pumpWidget(
      host(const Scaffold(body: FeaturedDictionary()), state, auth, device),
    );
    await tester.pumpAndSettle();
    expect(find.text('Từ trong dữ liệu'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.text('Từ trong dữ liệu'));
    await tester.pumpAndSettle();
    expect(find.text('/dictionary/real-entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'gallery selection saves image data and remove saves an empty avatar',
    (tester) async {
      final (state, fixture, auth, device) = await setup(tester);
      final profileReadsBeforeOpening = fixture.profileReads;
      await tester.pumpWidget(
        host(
          EditProfileScreen(
            avatarPicker: () async => AvatarSelection(base64Decode(png), 'png'),
          ),
          state,
          auth,
          device,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('URL ảnh đại diện (tùy chọn)'), findsNothing);
      await tester.tap(find.text('Chọn ảnh đại diện'));
      await tester.pumpAndSettle();
      final save = find.text('Lưu thay đổi');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        fixture.savedProfile?['avatarImage'],
        startsWith('data:image/png;base64,'),
      );
      expect(fixture.savedProfile?.containsKey('avatarUrl'), false);
      expect(
        fixture.profileReads,
        profileReadsBeforeOpening,
        reason:
            'Use the profile already synchronized before opening the editor.',
      );
      expect(
        fixture.settingsWrites,
        0,
        reason: 'Avatar-only changes do not save unchanged settings.',
      );
      expect(state.avatarUrl, startsWith('/user-media/avatars/'));
      await tester.ensureVisible(find.text('Bỏ ảnh đại diện'));
      await tester.tap(find.text('Bỏ ảnh đại diện'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(fixture.savedProfile?['avatarUrl'], '');
      expect(state.avatarUrl, '');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('notification error retries, marks read and opens review', (
    tester,
  ) async {
    final (state, fixture, auth, device) = await setup(tester);
    await tester.pumpWidget(
      host(const NotificationsScreen(), state, auth, device),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chưa tải được thông báo. Hãy thử lại.'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Đến lúc ôn lại'));
    await tester.tap(find.text('Đến lúc ôn lại'));
    await tester.pumpAndSettle();
    expect(fixture.read, true);
    expect(find.text('/learn?tab=1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'study schedule saves selected days independently from notifications',
    (tester) async {
      final (state, fixture, auth, device) = await setup(tester);
      await tester.pumpWidget(
        host(const StudyReminderScreen(), state, auth, device),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhắc học theo lịch'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'T2'));
      await tester.ensureVisible(find.text('Lưu cài đặt'));
      await tester.tap(find.text('Lưu cài đặt'));
      await tester.pumpAndSettle();
      expect(state.studyReminder.enabled, true);
      expect(state.studyReminder.weekdays, isNot(contains(1)));
      expect(fixture.settings['studyReminder']['weekdays'], hasLength(6));
      await tester.ensureVisible(find.text('Nhắc học theo lịch'));
      await tester.tap(find.text('Nhắc học theo lịch'));
      await tester.ensureVisible(find.text('Lưu cài đặt'));
      await tester.tap(find.text('Lưu cài đặt'));
      await tester.pumpAndSettle();
      expect(state.studyReminder.enabled, false);
      expect(state.notificationsEnabled, true);
      expect(tester.takeException(), isNull);
    },
  );
}
