// Manual device probe. This entry point is excluded from normal app builds.
// Run only against a development backend; credentials belong to an ephemeral QA account.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sign_voice/app.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/admin/admin_workspace_service.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/api/api_exception.dart';
import 'package:sign_voice/services/auth/auth_service.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/services/user/user_data_service.dart';

import '../test/auth_fixtures.dart' show MemoryTokenStore;

import 'package:sign_voice/services/notifications/notification_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(handleBackgroundPush);
  if (!const bool.fromEnvironment('FCM_TEST_PROBE')) {
    throw StateError('FCM_TEST_PROBE must be explicitly enabled.');
  }
  final file = File(
    '${Directory.systemTemp.parent.path}/files/signvoice-fcm-test.json',
  );
  final tokens = MemoryTokenStore();
  Map<String, dynamic> data = {};
  if (await file.exists()) {
    data = Map<String, dynamic>.from(jsonDecode(await file.readAsString()));
    tokens.accessToken = data['accessToken'] as String?;
    tokens.refreshToken = data['refreshToken'] as String?;
  }
  final api = ApiClient(tokenStorage: tokens, useRefreshCookie: false);
  final service = AuthService(apiClient: api, tokenStorage: tokens);
  final auth = AuthProvider(authService: service);
  try {
    await auth.initialize();
    if (!auth.isAuthenticated) {
      if (data['email'] != null) {
        if (!await auth.login(
          email: data['email'] as String,
          password: data['password'] as String,
        )) {
          throw StateError('Probe login failed.');
        }
      } else {
        final random = Random.secure();
        final suffix = List.generate(
          12,
          (_) => random.nextInt(16).toRadixString(16),
        ).join();
        data = {
          'email': 'qa-fcm-$suffix@example.test',
          'password':
              'Probe!${List.generate(24, (_) => random.nextInt(10)).join()}',
        };
        final user = await service.register(
          email: data['email'] as String,
          password: data['password'] as String,
          displayName: 'Kiểm thử thông báo',
        );
        data['userId'] = user.id;
        await auth.initialize();
      }
    }
    data.addAll({
      'userId': auth.user!.id,
      'accessToken': tokens.accessToken,
      'refreshToken': tokens.refreshToken,
    });
    await file.writeAsString(jsonEncode(data), flush: true);
    FirebaseMessaging.onMessage.listen(
      (message) =>
          debugPrint('FCM_PROBE_FOREGROUND ${message.data['notificationId']}'),
    );
    runApp(
      SignVoiceApp(
        auth: auth,
        state: AppState(service: UserDataService(apiClient: api)),
        adminService: AdminWorkspaceService(apiClient: api),
        learningService: LearningService(client: api),
        initialScreen: '/notifications',
      ),
    );
    debugPrint('FCM_PROBE_READY');
  } catch (error) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Không khởi tạo được thiết bị kiểm thử FCM.'),
          ),
        ),
      ),
    );
    debugPrint(
      'FCM_PROBE_SETUP_FAILED ${error.runtimeType} ${error is ApiException ? error.code : ''}',
    );
  }
}
