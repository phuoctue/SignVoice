import 'package:sign_voice/models/user_model.dart';
import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/auth/guest_trial_access.dart';
import 'package:sign_voice/widgets/guest_access_gate.dart';
import 'package:sign_voice/features/speech/speech_screens.dart';
import 'package:sign_voice/features/recognition/live_camera_screen.dart';
import 'package:sign_voice/services/auth/guest_device_identity.dart';

import 'auth_fixtures.dart';

import 'package:sign_voice/app.dart';
import 'package:sign_voice/services/learning/learning_service.dart';
import 'package:sign_voice/features/learning/learning_hub.dart';

import 'media_permissions_test.dart' show FakeSpeech, FakeCamera;

class TrialClock extends Stopwatch {
  Duration time = Duration.zero;
  @override
  Duration get elapsed => time;
  @override
  void reset() {
    time = Duration.zero;
  }
}

class TrialService extends FakeAuthService {
  TrialService() : super(restoredUser: testUser(guest: true));
  bool fail = false, expired = false;
  int grantCalls = 0;
  @override
  Future<UserModel> loginAsGuest() async {
    grantCalls++;
    return super.loginAsGuest();
  }

  @override
  Future<GuestTrialAccess> guestTrial() async {
    if (fail) throw StateError('offline');

    return GuestTrialAccess.fromJson({
      'state': expired ? 'expired' : 'active',
      'dataState': expired ? 'retained' : 'trial_active',
      'serverNow': '2026-10-24T00:00:00Z',
      'expiresAt': '2026-10-24T00:10:00Z',
      'dataVersion': 0,
      'allowedActions': [
        'status',
        'auth_me',
        'refresh',
        'logout',
        'convert',
        'discard',
      ],
    });
  }
}

Widget harness(
  AuthProvider auth,
  AppState state,
  Widget child, {
  bool personal = false,
}) => ChangeNotifierProvider.value(
  value: auth,
  child: AppScope(
    state: state,
    child: MaterialApp(
      home: GuestAccessGate(permanentOnly: personal, child: child),
      routes: {
        'S22': (_) => const Scaffold(body: Text('Kho công khai')),
        'S05': (_) => const Text('Đăng nhập tài khoản'),
        'S06': (_) => const Text('Tạo tài khoản cá nhân'),
      },
    ),
  ),
);
void main() {
  testWidgets(
    'restored guest keeps the same allowance without a new-grant prompt',
    (tester) async {
      final service = TrialService()..expired = true;
      final auth = AuthProvider(authService: service);
      await auth.initialize();
      final previous = auth.user!.id;
      final state = AppState();
      await tester.pumpWidget(
        SignVoiceApp(auth: auth, state: state, initialScreen: 'S10'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tạo khách mới · 10 phút'), findsNothing);
      expect(auth.user!.id, previous);
      expect(auth.trialExpired, isTrue);
      expect(service.grantCalls, 0);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      state.dispose();
    },
  );
  testWidgets(
    'expiry blocks studying deep links and keeps the public catalog readable',
    (tester) async {
      final clock = TrialClock();
      final service = TrialService();
      final provider = AuthProvider(authService: service, trialClock: clock);
      await provider.initialize();
      final state = AppState()..guest = true;
      clock.time = const Duration(minutes: 10);
      service.expired = true;
      for (final route in [
        '/learn?tab=1',
        '/learn/history',
        '/learn/insights',
      ]) {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: provider,
            child: AppScope(
              state: state,
              child: MaterialApp(
                home: AccessGate(key: ValueKey(route), screenId: route),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Đã hết thời gian dùng thử'), findsOneWidget);
        expect(find.byType(LearningHub), findsNothing);
      }
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: Provider<LearningService>.value(
            value: DemoLearningService(),
            child: AppScope(
              state: state,
              child: const MaterialApp(home: AccessGate(screenId: 'S22')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LearningHub), findsOneWidget);
      expect(find.text('Đã hết thời gian dùng thử'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      state.dispose();
    },
  );
  testWidgets('expiry closes a camera even while initialization is in flight', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final clock = TrialClock(), initialization = Completer<void>();
    final camera = FakeCamera(() => initialization.future);
    final auth = AuthProvider(authService: TrialService(), trialClock: clock);
    await auth.initialize();
    final state = AppState()..guest = true;
    await tester.pumpWidget(
      harness(
        auth,
        state,
        LiveCameraScreen(
          cameraFactory: ({required front}) => camera,
          ticketLoader: () async => 'unused',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cho phép camera'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(camera.closed, isFalse);
    clock.time = const Duration(minutes: 10);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(camera.closed, isTrue);
    expect(find.text('Đã hết thời gian dùng thử'), findsOneWidget);
    initialization.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    state.dispose();
  });
  testWidgets(
    'status never grants, counts down and stops microphone at expiry while preserving drafts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = TrialClock(), service = TrialService();
      final auth = AuthProvider(authService: service, trialClock: clock);
      await auth.initialize();
      final state = AppState();
      final input = FakeSpeech(grant: true);
      await tester.pumpWidget(
        harness(auth, state, SpeechCaptureScreen(input: input)),
      );
      await tester.pumpAndSettle();
      expect(service.grantCalls, 0);
      expect(input.requests, 0);
      expect(find.text('Dùng thử · còn 10:00'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Cho phép microphone'),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(input.listening, isTrue);
      input.text = 'Bản nháp còn nguyên';
      input.notifyListeners();
      await tester.pump();
      clock.time = const Duration(minutes: 10);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(input.listening, isFalse);
      expect(find.text('Đã hết thời gian dùng thử'), findsOneWidget);
      expect(find.text('Bản nháp còn nguyên'), findsOneWidget);
      expect(auth.isAuthenticated, isTrue);
      await tester.ensureVisible(find.text('Xem từ điển công khai'));
      await tester.tap(find.text('Xem từ điển công khai'));
      await tester.pumpAndSettle();
      expect(find.text('Kho công khai'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      state.dispose();
    },
  );
  testWidgets('personal actions require an account during the active trial', (
    tester,
  ) async {
    final service = TrialService(), state = AppState();
    final auth = AuthProvider(authService: service);
    await auth.initialize();
    await tester.pumpWidget(
      harness(auth, state, const Text('Saved content'), personal: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cần tài khoản cá nhân'), findsOneWidget);
    expect(find.text('Saved content'), findsNothing);
    expect(service.grantCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.dispose();
    state.dispose();
  });
  testWidgets(
    'status errors fail closed and permit retry without opening sensitive input',
    (tester) async {
      final service = TrialService()..fail = true;
      final auth = AuthProvider(authService: service);
      await auth.initialize();
      final state = AppState();
      await tester.pumpWidget(
        harness(auth, state, const Text('Camera opened')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Camera opened'), findsNothing);
      service.fail = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Camera opened'), findsOneWidget);
      expect(find.text('Bắt đầu phiên thử 10 phút'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      state.dispose();
    },
  );
  test(
    'device allowance key survives ordinary subsequent guest entry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = await guestDeviceKey();
      expect(first, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(await guestDeviceKey(), first);
    },
  );
}
