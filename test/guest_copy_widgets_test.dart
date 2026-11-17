import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_voice/core/app_state.dart';
import 'package:sign_voice/features/auth/auth_screens.dart';
import 'package:sign_voice/providers/auth_provider.dart';
import 'package:sign_voice/services/api/api_client.dart';
import 'package:sign_voice/services/auth/auth_service.dart';
import 'package:sign_voice/widgets/guest_data_panel.dart';

import 'auth_fixtures.dart';
import 'guest_v1_service_test.dart' show envelope, trialStatus;

const approvedStart =
    'Bạn được dùng thử 10 phút. Đóng ứng dụng không làm dừng hay đặt lại thời gian. Dữ liệu khách được giữ 7 ngày; muốn giữ lâu hơn, hãy tạo tài khoản. Mỗi thiết bị được thử lại sau 24 giờ.';
const approvedPrivacy =
    'Dữ liệu khách được giữ 7 ngày. Sau đó bạn không xem hay chuyển được nữa, nhưng vẫn có thể tự xóa. Bản sao lưu dùng để khôi phục sự cố có thể còn dữ liệu tới khoảng 3 tháng.';
const ambiguousGrant =
    'Chưa xác nhận được lượt thử. Hãy kiểm tra kết nối và thử lại cùng yêu cầu.';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final desktop in [false, true]) {
    final layout = desktop ? 'web keyboard' : 'mobile 200% semantics';
    Future<AuthProvider> mount(
      WidgetTester tester, {
      bool guest = true,
      bool offlineStatus = false,
      bool rejectGrant = false,
      Map<String, dynamic>? status,
      Widget child = const GuestDataPanel(),
    }) async {
      tester.view.physicalSize = desktop
          ? const Size(1280, 900)
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryTokenStore()..accessToken = guest ? 'guest' : null;
      final api = ApiClient(
        tokenStorage: store,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/providers')) {
            return envelope({'google': false, 'facebook': false});
          }
          if (r.url.path.endsWith('/me')) {
            return envelope(testUser(guest: true).toJson());
          }
          if (r.method == 'POST') {
            if (!rejectGrant) throw http.ClientException('lost response');
            return http.Response(
              '{"error":{"code":"CONFLICT","message":"known rejection"},'
              '"data":{"nextTrialAvailableAt":"2026-11-18T00:00:00Z"}}',
              409,
            );
          }
          if (offlineStatus) throw http.ClientException('offline');
          return envelope(status ?? trialStatus('retained'));
        }),
      );
      final auth = AuthProvider(
        authService: AuthService(apiClient: api, tokenStorage: store),
      );
      final state = AppState();
      await auth.initialize();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: AppScope(
            state: state,
            child: MaterialApp(
              theme: ThemeData(
                platform: desktop
                    ? TargetPlatform.windows
                    : TargetPlatform.android,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(desktop ? 1 : 2)),
                child: child!,
              ),
              home: child is GuestDataPanel
                  ? Scaffold(body: SingleChildScrollView(child: child))
                  : child,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
        api.dispose();
        state.dispose();
      });
      return auth;
    }

    for (final hasDate in [false, true]) {
      testWidgets('$layout legacy deadline date=$hasDate and RS1 agree', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final status = trialStatus('legacy_unknown', eligible: true);
        status['dataRetainedUntil'] = hasDate
            ? DateTime(2030, 1, 2, 3, 4).toUtc().toIso8601String()
            : null;
        final auth = await mount(tester, status: status);
        final deadline = find.text(
          hasDate
              ? 'Hạn giữ dữ liệu: 03:04 02/01/2030'
              : 'Hạn giữ dữ liệu: chưa xác định từ máy chủ',
        );
        expect(deadline, findsOneWidget);
        expect(
          tester.getSemantics(deadline).getSemanticsData().label,
          contains(hasDate ? '03:04 02/01/2030' : 'chưa xác định'),
        );
        expect(find.byKey(const ValueKey('guest-replace')), findsNothing);
        expect(find.byKey(const ValueKey('guest-convert')), findsOneWidget);
        expect(find.byKey(const ValueKey('guest-discard')), findsOneWidget);
        final logout = find.byKey(const ValueKey('guest-logout'));
        await tester.ensureVisible(logout);
        await tester.tap(logout);
        await tester.pumpAndSettle();
        final message = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
            hasDate
                ? 'Hạn giữ hoặc chuyển dữ liệu của phiên này là 03:04 02/01/2030'
                : 'Máy chủ chưa xác định hạn giữ dữ liệu',
          ),
        );
        expect(message, findsOneWidget);
        expect(
          tester.getSemantics(message).getSemanticsData().label,
          contains(hasDate ? '03:04 02/01/2030' : 'chưa xác định'),
        );
        await tester.tap(find.text('Ở lại'));
        await tester.pumpAndSettle();
        expect(auth.isAuthenticated, true);
        expect(
          find.text('Chưa xác định thời hạn dữ liệu khách'),
          hasDate ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }

    testWidgets('$layout privacy summary and accessible details', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await mount(tester);
      expect(find.text(approvedPrivacy), findsOneWidget);
      expect(find.text(guestPrivacyNotice), findsNothing);
      final details = find.text('Chi tiết');
      await tester.ensureVisible(details);
      expect(
        tester.getSemantics(details).getSemanticsData().label,
        contains('Chi tiết'),
      );
      if (desktop) {
        var focused = false;
        for (var i = 0; i < 12 && !focused; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final focusContext = FocusManager.instance.primaryFocus?.context;
          focused =
              focusContext != null &&
              find
                  .ancestor(
                    of: find.byWidget(focusContext.widget),
                    matching: find.byType(ExpansionTile),
                  )
                  .evaluate()
                  .isNotEmpty;
        }
        expect(focused, true, reason: 'Tab must reach the Chi tiết expander');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(details);
      }
      await tester.pumpAndSettle();
      final fullPrivacy = find.text(guestPrivacyNotice);
      expect(fullPrivacy, findsOneWidget);
      await tester.ensureVisible(fullPrivacy);
      expect(
        tester.getSemantics(fullPrivacy).getSemanticsData().label,
        contains('không dùng lại dữ liệu khách cho sản phẩm'),
      );
      expect(guestPrivacyNotice, contains('92 ngày'));
      expect(guestPrivacyNotice, contains('chưa có giới hạn tối đa hữu hạn'));
      expect(guestPrivacyNotice, contains('90 ngày'));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('$layout failed status has accurate RS1 copy', (tester) async {
      final auth = await mount(tester, offlineStatus: true);
      expect(auth.trial, isNull);
      expect(auth.trialError, isNotNull);
      final logout = find.byKey(const ValueKey('guest-logout'));
      await tester.ensureVisible(logout);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Chưa tải được hạn giữ dữ liệu…'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Máy chủ chưa xác định'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Ở lại'));
      await tester.pumpAndSettle();
      expect(auth.isAuthenticated, true);
      expect(tester.takeException(), isNull);
    });

    for (final reject in [false, true]) {
      testWidgets(
        '$layout concise start and ${reject ? 'known rejection' : 'ambiguous guidance'}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await mount(
            tester,
            guest: false,
            rejectGrant: reject,
            child: const AuthScreen(),
          );
          final start = find.text(
            desktop && kIsWeb
                ? 'Khám phá bản dùng thử'
                : 'Dùng thử không cần tài khoản',
          );
          await tester.ensureVisible(start);
          await tester.tap(start);
          await tester.pumpAndSettle();
          expect(find.text(approvedStart), findsOneWidget);
          expect(find.textContaining('cùng yêu cầu'), findsNothing);
          expect(
            tester
                .getSemantics(find.text(approvedStart))
                .getSemanticsData()
                .label,
            approvedStart,
          );
          await tester.ensureVisible(find.text('Vào dùng thử'));
          await tester.tap(find.text('Vào dùng thử'));
          await tester.pumpAndSettle();
          expect(
            find.text(ambiguousGrant),
            reject ? findsNothing : findsOneWidget,
          );
          if (reject) {
            expect(find.textContaining('Thử lại lúc'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}
