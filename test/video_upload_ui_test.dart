import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sign_voice/models/user_model.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/screens/admin/admin_management_screens.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';

import 'auth_fixtures.dart';

class UploadService extends AdminWorkspaceService {
  List<int>? uploaded;
  @override
  Future<List<AdminRecord>> activeCategories() async => [
    {'_id': '123123123123123123123123', 'name': 'Chào hỏi'},
  ];
  @override
  Future<String> uploadVideoStream(
    Stream<List<int>> Function() openStream,
    int length,
  ) async {
    uploaded = await openStream().expand((chunk) => chunk).toList();
    return 'http://localhost:3000/sign-media/selected.mp4';
  }
}

void main() {
  testWidgets('selecting a local MOV fills the converted MP4 video URL', (
    tester,
  ) async {
    final folder = Directory.systemTemp.createTempSync('signvoice-video-ui-');
    addTearDown(() => folder.deleteSync(recursive: true));
    final bytes = [
      0,
      0,
      0,
      24,
      102,
      116,
      121,
      112,
      109,
      112,
      52,
      50,
      0,
      0,
      0,
      0,
    ];
    final file = File('${folder.path}/greeting.mov')..writeAsBytesSync(bytes);
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'pickVideo');
      return file.path;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final auth = AuthProvider(
      authService: FakeAuthService(
        restoredUser: testUser(role: UserRole.admin),
      ),
    );
    await auth.initialize();
    addTearDown(auth.dispose);
    final service = UploadService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<AdminWorkspaceService>.value(value: service),
        ],
        child: const MaterialApp(
          home: AdminEditorScreen(resource: 'dictionary'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Chọn video từ máy'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Chọn video từ máy'));
      for (var i = 0; i < 100 && service.uploaded == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(service.uploaded, bytes);
    final videoField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'URL video ký hiệu'),
    );
    expect(
      videoField.controller!.text,
      'http://localhost:3000/sign-media/selected.mp4',
    );
    expect(find.textContaining('Đã tải lên: greeting.mov'), findsOneWidget);
    expect(find.text('Đang tải và xử lý video...'), findsNothing);
  });
}
