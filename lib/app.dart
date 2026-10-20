import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/staff_provider.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/admin_management_screens.dart';
import 'services/admin/admin_workspace_service.dart';
import 'screens/staff/staff_dashboard_screen.dart';

import 'core/app_state.dart';
import 'core/theme.dart';
import 'core/navigation.dart';
import 'features/auth/auth_screens.dart';
import 'features/auth/oauth_complete_screen.dart';
import 'features/home/home_screen.dart';
import 'features/recognition/recognition_screens.dart';
import 'features/speech/speech_screens.dart';
import 'features/library/library_screens.dart';
import 'features/profile/profile_screens.dart';
import 'features/system/system_screens.dart';
import 'features/recognition/live_camera_screen.dart';

class SignVoiceApp extends StatefulWidget {
  const SignVoiceApp({
    super.key,
    this.initialScreen = 'S01',
    this.state,
    this.auth,
    this.adminService,
  });
  final String initialScreen;
  final AppState? state;
  final AuthProvider? auth;
  final AdminWorkspaceService? adminService;
  @override
  State<SignVoiceApp> createState() => _SignVoiceAppState();
}

class _SignVoiceAppState extends State<SignVoiceApp> {
  late final AppState state = widget.state ?? AppState();
  late final AuthProvider auth = widget.auth ?? AuthProvider();
  late final AdminWorkspaceService adminService =
      widget.adminService ?? AdminWorkspaceService();
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    auth.addListener(_syncUser);
    final callback =
        Uri.base.path == '/oauth-complete' ||
        Uri.base.fragment.split('?').first == '/oauth-complete';
    if (auth.state == AuthState.initial && !callback) auth.initialize();
    _syncUser();
  }

  void _syncUser() {
    final user = auth.user;
    if (auth.isAuthenticated && user != null) {
      if (_currentUserId != user.id) {
        _currentUserId = user.id;
        state.bindAccount(
          user.id,
          asGuest: user.isGuest,
          displayName: user.displayName,
          userEmail: user.email ?? '',
        );
      } else {
        state.enter(
          asGuest: user.isGuest,
          displayName: user.displayName,
          userEmail: user.email ?? '',
        );
      }
    } else if (auth.state == AuthState.unauthenticated) {
      _currentUserId = null;
      state.clearLocalData();
      state.enter(asGuest: false, displayName: '', userEmail: '');
    }
  }

  @override
  void dispose() {
    auth.removeListener(_syncUser);
    if (widget.auth == null) auth.dispose();
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      Provider.value(value: adminService),
    ],
    child: AppScope(
      state: state,
      child: AnimatedBuilder(
        animation: state,
        builder: (context, child) => MaterialApp(
          title: 'SignVoice',
          debugShowCheckedModeBanner: false,
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: makeTheme(dark: false, highContrast: state.highContrast),
          darkTheme: makeTheme(dark: true, highContrast: state.highContrast),
          themeMode: state.themeMode,
          onGenerateInitialRoutes: (initialRoute) {
            final uri = Uri.tryParse(initialRoute);
            if (uri?.path == '/oauth-complete') {
              return [
                MaterialPageRoute<void>(
                  settings: RouteSettings(name: initialRoute),
                  builder: (_) =>
                      OAuthCompleteScreen(error: uri!.queryParameters['error']),
                ),
              ];
            }
            // Build the reset page alone: a background splash timer must not
            // redirect the user away from the link opened from their email.
            if (uri?.path == '/reset-password') {
              return [
                MaterialPageRoute<void>(
                  settings: RouteSettings(name: initialRoute),
                  builder: (_) => ResetPasswordScreen(
                    token: uri!.queryParameters['token'] ?? '',
                  ),
                ),
              ];
            }
            return [
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '/'),
                builder: (_) => AccessGate(
                  screenId:
                      screenNames.containsKey(initialRoute) ||
                          initialRoute == 'admin' ||
                          initialRoute.startsWith('/admin/')
                      ? initialRoute
                      : widget.initialScreen,
                ),
              ),
            ];
          },
          routes: {
            '/': (_) => AccessGate(screenId: widget.initialScreen),
            for (final id in screenNames.keys)
              id: (_) => AccessGate(screenId: id),
            'catalog': (_) => const AccessGate(screenId: 'catalog'),
            'admin': (_) => const AccessGate(screenId: 'admin'),
            for (final resource in [...adminModules.keys, 'content'])
              '/admin/$resource': (_) =>
                  AccessGate(screenId: '/admin/$resource'),
            'staff': (_) => const AccessGate(screenId: 'staff'),
          },
          onGenerateRoute: (settings) {
            final uri = Uri.tryParse(settings.name ?? '');
            if (uri?.path == '/oauth-complete') {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) =>
                    OAuthCompleteScreen(error: uri!.queryParameters['error']),
              );
            }
            if (uri?.path == '/reset-password') {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => ResetPasswordScreen(
                  token: uri!.queryParameters['token'] ?? '',
                ),
              );
            }
            return null;
          },
          builder: (context, navigator) {
            final media = MediaQuery.of(context);
            final content = MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(
                  media.textScaler.scale(1) * state.fontScale,
                ),
              ),
              child: navigator!,
            );
            // Mobile lấp đầy màn hình; desktop/Chrome có khung điện thoại để demo.
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) return content;
                return ColoredBox(
                  color: const Color(0xFFE2E8F0),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      constraints: const BoxConstraints(
                        maxWidth: 440,
                        maxHeight: 920,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x260F172A),
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: content,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ),
  );
}

class AccessGate extends StatelessWidget {
  const AccessGate({super.key, required this.screenId});
  final String screenId;

  @override
  Widget build(BuildContext context) {
    if (const {
      'S01',
      'S02',
      'S03',
      'S04',
      'S05',
      'S06',
      'S07',
    }.contains(screenId)) {
      return screenFor(screenId);
    }
    final auth = context.watch<AuthProvider>();
    if (auth.state == AuthState.initial || auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthenticated) return const AuthScreen();
    final isAdminRoute = screenId == 'admin' || screenId.startsWith('/admin/');
    final resource = screenId.split('/').last;
    final permission = resource == 'content'
        ? 'dictionary:read'
        : '$resource:read';
    if ((isAdminRoute &&
            (!auth.isAdmin ||
                (screenId != 'admin' && !auth.can(permission)))) ||
        (screenId == 'staff' && !auth.isStaff)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quyền truy cập')),
        body: const Center(
          child: Text('Bạn không có quyền truy cập trang này.'),
        ),
      );
    }
    if (screenId == 'admin') {
      return const AdminDashboardScreen();
    }
    if (isAdminRoute) {
      return AdminResourceScreen(
        resource: resource == 'content' ? 'dictionary' : resource,
        review: resource == 'content',
      );
    }
    if (screenId == 'staff') {
      return ChangeNotifierProvider(
        create: (_) => StaffProvider(),
        child: const StaffDashboardScreen(),
      );
    }
    return screenFor(screenId);
  }
}

Widget screenFor(String id) => switch (id) {
  'S01' => const SplashScreen(),
  'S02' => const OnboardingScreen(index: 0),
  'S03' => const OnboardingScreen(index: 1),
  'S04' => const OnboardingScreen(index: 2),
  'S05' => const AuthScreen(),
  'S06' => const AuthScreen(register: true),
  'S07' => const ForgotPasswordScreen(),
  'S08' => const HomeScreen(),
  'S09' => const LiveCameraScreen(),
  'S10' => const LiveCameraScreen(),
  'S11' => const LiveCameraScreen(),
  'S12' => const LiveCameraScreen(),
  'S13' => const SentenceScreen(),
  'S14' => const VoicePlaybackScreen(),
  'S15' => const PermissionScreen(camera: false),
  'S16' => const SpeechCaptureScreen(),
  'S17' => const SpeechCaptureScreen(listening: true),
  'S18' => const TranscriptScreen(),
  'S19' => const TranscriptScreen(fullscreen: true),
  'S20' => const HistoryScreen(),
  'S21' => const HistoryDetailScreen(),
  'S22' => const DictionaryScreen(),
  'S23' => const SignDetailScreen(),
  'S24' => const DictionaryScreen(favoritesOnly: true),
  'S25' => const ProfileScreen(),
  'S26' => const EditProfileScreen(),
  'S27' => const VoiceSettingsScreen(),
  'S28' => const AppearanceScreen(),
  'S29' => const SyncScreen(),
  'S30' => const PrivacyScreen(),
  'S31' => const AboutScreen(),
  'SS01' ||
  'SS02' ||
  'SS03' ||
  'SS04' ||
  'SS05' ||
  'SS06' => SystemScreen(id: id),
  'ai_vision' => const LiveCameraScreen(),
  _ => const ScreenCatalog(),
};
