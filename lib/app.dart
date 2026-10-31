import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/admin_management_screens.dart';
import 'screens/admin/collection_moderation_screen.dart';
import 'services/admin/admin_workspace_service.dart';
import 'screens/staff/staff_workspace_screen.dart';
import 'services/user/user_data_service.dart';
import 'services/staff/staff_workspace_service.dart';

import 'core/app_state.dart';
import 'core/app_route.dart';
import 'core/theme.dart';
import 'core/navigation.dart';
import 'features/auth/auth_screens.dart';
import 'features/auth/oauth_complete_screen.dart';
import 'features/auth/change_password_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/communication_hub.dart';
import 'features/recognition/recognition_screens.dart';
import 'features/speech/speech_screens.dart';
import 'features/library/library_screens.dart';
import 'features/profile/profile_screens.dart';
import 'features/system/system_screens.dart';
import 'features/recognition/live_camera_screen.dart';
import 'widgets/guest_access_gate.dart';
import 'widgets/ui.dart';
import 'widgets/web_workspace.dart';
import 'features/learning/learning_hub.dart';
import 'features/learning/learning_history_screen.dart';
import 'features/learning/learning_insights_screen.dart';
import 'features/learning/recall_review_quiz_screen.dart';
import 'features/learning/collection_screens.dart';
import 'features/learning/topic_learning_screen.dart';
import 'services/learning/learning_service.dart';
import 'services/api/api_client.dart';
import 'services/notifications/notification_service.dart';
import 'features/notifications/notification_screens.dart';

class SignVoiceApp extends StatefulWidget {
  const SignVoiceApp({
    super.key,
    this.initialScreen = 'S01',
    this.state,
    this.auth,
    this.adminService,
    this.staffService,
    this.learningService,
    this.enableLibraryUpdates = false,
    this.webRouting,
  });
  final String initialScreen;
  final AppState? state;
  final AuthProvider? auth;
  final AdminWorkspaceService? adminService;
  final StaffWorkspaceService? staffService;
  final LearningService? learningService;
  final bool enableLibraryUpdates;
  final bool? webRouting;
  @override
  State<SignVoiceApp> createState() => _SignVoiceAppState();
}

class _SignVoiceAppState extends State<SignVoiceApp>
    with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  final _exitGuards = <String, AppRouteExitController>{};
  String? _renderedWebLocation;
  bool get useWebRouter => widget.webRouting ?? kIsWeb;
  late final GoRouter webRouter = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: webLocation(widget.initialScreen),
    redirect: (context, state) async {
      if (state.uri.path == '/') {
        return widget.initialScreen == 'S01' ? '/home' : null;
      }
      if (state.uri.path == '/welcome') {
        return state.uri.replace(path: '/home').toString();
      }
      final canonical = webLocation(legacyLocation(state.uri.toString()));
      if (canonical != state.uri.toString()) return canonical;
      final previous = _renderedWebLocation;
      if (previous != null && Uri.parse(previous).path != state.uri.path) {
        final guard = _exitGuards[Uri.parse(previous).path];
        if (guard?.handler != null && !await guard!.allowExit()) {
          return previous;
        }
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, route, child) =>
            _WebShell(uri: route.uri, child: child),
        routes: [
          for (final path in [
            '/',
            '/:section',
            '/:section/:id',
            '/:section/:id/:action',
          ])
            GoRoute(
              path: path,
              onExit: (context, state) async {
                final key = state.uri.path;
                final allowed = await _exitGuards[key]?.allowExit() ?? true;
                if (allowed) _exitGuards.remove(key);
                return allowed;
              },
              pageBuilder: (context, state) {
                _renderedWebLocation = state.uri.toString();
                return CustomTransitionPage<void>(
                  transitionDuration: const Duration(milliseconds: 160),
                  reverseTransitionDuration: const Duration(milliseconds: 100),
                  transitionsBuilder: (context, animation, secondary, child) =>
                      MediaQuery.disableAnimationsOf(context)
                      ? child
                      : FadeTransition(opacity: animation, child: child),
                  key: ValueKey('${state.pageKey.value}:${state.uri.path}'),
                  name: legacyLocation(state.uri.toString()),
                  arguments: state.extra,
                  child: AppRouteExitScope(
                    controller: _exitGuards.putIfAbsent(
                      state.uri.path,
                      AppRouteExitController.new,
                    ),
                    child: _screen(
                      RouteSettings(
                        name: legacyLocation(state.uri.toString()),
                        arguments: state.extra,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        _screen(RouteSettings(name: state.uri.toString())),
  );
  void _openNotification(String route) {
    if (useWebRouter) {
      webRouter.push(webLocation(route));
    } else {
      navigatorKey.currentState?.pushNamed(route);
    }
  }

  String? pendingNotificationRoute;
  late final notifications = NotificationService(
    state,
    onOpen: (route) {
      if (navigatorKey.currentState == null) {
        pendingNotificationRoute = route;
      } else {
        _openNotification(route);
      }
    },
  );
  late final AppState state =
      widget.state ?? AppState(service: StartupUserDataService());
  late final AuthProvider auth = widget.auth ?? AuthProvider();
  late final AdminWorkspaceService adminService =
      widget.adminService ?? AdminWorkspaceService();
  late final LearningService learningService =
      widget.learningService ?? LearningService();
  String? _currentUserId;
  bool _notificationsStarted = false;
  Timer? _libraryTimer;
  bool _checkingLibrary = false;
  Future<void> _checkLibrary() async {
    if (_checkingLibrary || !mounted) return;
    _checkingLibrary = true;
    try {
      await ApiClient.instance.refreshLibraryRevision();
    } catch (_) {
      /* Retry on resume/next interval. */
    } finally {
      _checkingLibrary = false;
    }
  }

  void _watchLibrary() {
    if (!widget.enableLibraryUpdates) return;
    _libraryTimer?.cancel();
    unawaited(_checkLibrary());
    _libraryTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_checkLibrary()),
    );
  }

  @override
  void initState() {
    super.initState();
    if (useWebRouter) GoRouter.optionURLReflectsImperativeAPIs = true;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pendingNotificationRoute != null && mounted) {
        _openNotification(pendingNotificationRoute!);
        pendingNotificationRoute = null;
      }
    });
    auth.addListener(_syncUser);
    final callback =
        Uri.base.path == '/oauth-complete' ||
        Uri.base.fragment.split('?').first == '/oauth-complete';
    if (auth.state == AuthState.initial && !callback) auth.initialize();
    _syncUser();
    _watchLibrary();
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
          userAvatarUrl: user.avatarUrl,
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
      state.unbindAccount();
    }
    if (!_notificationsStarted &&
        (auth.isAuthenticated || auth.state == AuthState.unauthenticated)) {
      _notificationsStarted = true;
      notifications.start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      _watchLibrary();
    } else if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached ||
        lifecycle == AppLifecycleState.hidden) {
      _libraryTimer?.cancel();
    }
    if (_notificationsStarted && lifecycle == AppLifecycleState.resumed) {
      auth.refreshUser();
      if (kIsWeb && state.persisted && auth.isAuthenticated && !state.syncing) {
        unawaited(state.synchronize());
      }
      notifications.refreshInbox();
      notifications.retry();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    notifications.dispose();
    if (useWebRouter) webRouter.dispose();
    _libraryTimer?.cancel();
    auth.removeListener(_syncUser);
    if (widget.auth == null) auth.dispose();
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  Route<void> _route(RouteSettings settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => _screen(settings),
  );

  Widget _screen(RouteSettings settings) {
    final location = settings.name == '/'
        ? widget.initialScreen
        : settings.name ?? '';
    final route = AppRoute.parse(
      location,
      adminResources: [...adminModules.keys, 'content'],
    );

    if (!route.known) {
      return AppPage(
        title: 'Không tìm thấy trang',
        child: EmptyView(
          title: 'Liên kết không hợp lệ',
          description: 'Trang này không tồn tại hoặc liên kết đã thay đổi.',
          action: Builder(
            builder: (context) => TextButton(
              onPressed: () => backOrHome(context),
              child: const Text('Quay lại'),
            ),
          ),
        ),
      );
    }
    if (route.uri.path == '/oauth-complete') {
      return OAuthCompleteScreen(error: route.uri.queryParameters['error']);
    }
    if (route.uri.path == '/reset-password') {
      return ResetPasswordScreen(
        token: route.uri.queryParameters['token'] ?? '',
      );
    }
    if (route.uri.pathSegments.length == 3 &&
        route.uri.pathSegments[0] == 'collections' &&
        route.uri.pathSegments[1] == 'shared') {
      return SharedSignCollectionScreen(code: route.uri.pathSegments[2]);
    }
    if (route.uri.path == '/collections/discover') {
      return const PublicSignCollectionsScreen();
    }
    final id = route.screenId!;
    final libraryRoute =
        const {'S08', 'S22', 'S23', 'S24', 'catalog'}.contains(id) ||
        (id.startsWith('/learn') &&
            id != '/learn/personal' &&
            id != '/learn?tab=2') ||
        id.startsWith('/dictionary/') ||
        id.startsWith('/admin/dictionary') ||
        id.startsWith('/staff/content');
    return libraryRoute
        ? _LibraryBoundary(builder: () => AccessGate(screenId: id))
        : AccessGate(screenId: id);
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: notifications),
      Provider.value(value: adminService),
      Provider.value(value: learningService),
      Provider.value(value: widget.staffService ?? StaffWorkspaceService()),
    ],
    child: AppScope(
      state: state,
      child: AnimatedBuilder(
        animation: state,
        builder: (context, child) => useWebRouter
            ? MaterialApp.router(
                routerConfig: webRouter,
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
                darkTheme: makeTheme(
                  dark: true,
                  highContrast: state.highContrast,
                ),
                themeMode: state.themeMode,
                builder: _appBuilder,
              )
            : MaterialApp(
                title: 'SignVoice',
                navigatorKey: navigatorKey,
                debugShowCheckedModeBanner: false,
                locale: const Locale('vi'),
                supportedLocales: const [Locale('vi'), Locale('en')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: makeTheme(dark: false, highContrast: state.highContrast),
                darkTheme: makeTheme(
                  dark: true,
                  highContrast: state.highContrast,
                ),
                themeMode: state.themeMode,
                // Share route parsing for startup links and navigation within the app.
                // A reset/OAuth link must never mount a splash timer behind its page.
                onGenerateInitialRoutes: (location) => [
                  _route(RouteSettings(name: location)),
                ],
                onGenerateRoute: _route,
                builder: _appBuilder,
              ),
      ),
    ),
  );
  Widget _appBuilder(BuildContext context, Widget? navigator) {
    final media = MediaQuery.of(context);
    final content = MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(
          media.textScaler.scale(1) * state.fontScale,
        ),
      ),
      child: navigator!,
    );
    // Web owns the full browser viewport; pages adapt to its constraints.
    if (kIsWeb) return content;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktopFrame =
            kIsWeb ||
            switch (defaultTargetPlatform) {
              TargetPlatform.windows ||
              TargetPlatform.macOS ||
              TargetPlatform.linux => true,
              _ => false,
            };
        if (!desktopFrame || constraints.maxWidth < 600) return content;
        return ColoredBox(
          color: const Color(0xFFE2E8F0),
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(16),
              constraints: const BoxConstraints(maxWidth: 440, maxHeight: 920),
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
  }
}

class _WebShell extends StatelessWidget {
  const _WebShell({required this.uri, required this.child});
  final Uri uri;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final publicAuth = const {
      '/login',
      '/register',
      '/welcome',
      '/home',
      '/forgot-password',
      '/reset-password',
      '/oauth-complete',
    }.contains(uri.path);
    final page =
        MediaQuery.sizeOf(context).width < 900 ||
            !auth.isAuthenticated ||
            publicAuth
        ? child
        : WebWorkspace(uri: uri, child: child);
    final title = uri.path.startsWith('/learn/quiz/')
        ? 'Ôn ký hiệu'
        : uri.path.startsWith('/learn/topic/')
        ? 'Học ký hiệu'
        : screenNames[legacyLocation(uri.path)] ?? 'SignVoice';
    return Title(
      title: title == 'SignVoice' ? title : '$title · SignVoice',
      color: Theme.of(context).colorScheme.primary,
      child: page,
    );
  }
}

class _LibraryBoundary extends StatelessWidget {
  const _LibraryBoundary({required this.builder});
  final Widget Function() builder;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: ApiClient.instance.libraryChanged,
    builder: (_, revision, _) =>
        KeyedSubtree(key: ValueKey('library-$revision'), child: builder()),
  );
}

class AccessGate extends StatelessWidget {
  const AccessGate({
    super.key,
    required this.screenId,
    this.guestChecked = false,
  });
  final bool guestChecked;
  final String screenId;

  @override
  Widget build(BuildContext context) {
    if (screenId == 'S01' && (kIsWeb || GoRouter.maybeOf(context) != null)) {
      return const WebLandingPage();
    }
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
    if (!auth.isAuthenticated) {
      if (screenId == 'S22' || screenId == '/dictionary/browse') {
        return const DictionaryScreen();
      }
      if (screenId.startsWith('/dictionary/')) {
        return SignDetailScreen(
          entryId: Uri.decodeComponent(screenId.split('/').last),
        );
      }
      return AuthScreen(returnRoute: screenId);
    }
    final state = AppScope.of(context);
    if (state.persisted && !state.ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dữ liệu tài khoản')),
        body: Center(
          child: state.syncing
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(state.error ?? 'Không tải được dữ liệu.'),
                    ),
                    FilledButton(
                      onPressed: state.synchronize,
                      child: const Text('Thử lại'),
                    ),
                    TextButton(
                      onPressed: auth.logout,
                      child: const Text('Đăng xuất'),
                    ),
                  ],
                ),
        ),
      );
    }
    if (auth.user?.isGuest == true && !guestChecked) {
      final uri = Uri.parse(screenId);
      final publicCatalog =
          const {'S22', 'S23', 'catalog', 'S27', 'S28'}.contains(screenId) ||
          screenId.startsWith('/dictionary/') ||
          (uri.path.startsWith('/learn/topic/') &&
              uri.queryParameters['study'] != '1');
      if (!publicCatalog) {
        final permanent =
            const {
              'S20',
              'S21',
              'S24',
              'S25',
              'S26',
              'S27',
              'S28',
              'S29',
              'S30',
              'S31',
              '/study-reminder',
              '/notifications',
              '/learn/personal',
            }.contains(screenId) ||
            screenId.startsWith('/collections/') ||
            uri.path == '/learn' && uri.queryParameters['tab'] == '2';
        return GuestAccessGate(
          permanentOnly: permanent,
          child: AccessGate(screenId: screenId, guestChecked: true),
        );
      }
    }
    final isAdminRoute = screenId == 'admin' || screenId.startsWith('/admin/');
    final resource = screenId.startsWith('/admin/collections/')
        ? 'collections'
        : screenId.split('/').last;
    final permission = resource == 'content'
        ? 'dictionary:read'
        : '$resource:read';
    if ((isAdminRoute &&
            (!auth.isStaff ||
                (screenId != 'admin' &&
                    (!auth.can(permission) ||
                        (const [
                              'users',
                              'roles',
                              'sessions',
                            ].contains(resource) &&
                            !auth.isAdmin))))) ||
        ((screenId == 'staff' || screenId.startsWith('/staff/')) &&
            (!auth.isStaff ||
                (screenId.startsWith('/staff/users') &&
                    (!auth.isAdmin || !auth.can('users:read'))) ||
                (screenId.startsWith('/staff/content') &&
                    !auth.can('dictionary:read'))))) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quyền truy cập')),
        body: const Center(
          child: Text('Bạn không có quyền truy cập trang này.'),
        ),
      );
    }
    if (screenId.startsWith('/collections/')) {
      final parts = Uri.parse(screenId).pathSegments;
      if (parts.length == 3 && parts[1] == 'save') {
        return SignCollectionsScreen(saveEntryId: parts[2]);
      }
      if (parts.length == 3 && const {'add', 'personal'}.contains(parts[2])) {
        return CollectionWordPickerScreen(
          id: parts[1],
          personal: parts[2] == 'personal',
        );
      }
      return SignCollectionScreen(id: parts[1]);
    }
    if (screenId == '/learn/personal') {
      return const SignCollectionsScreen();
    }
    if (screenId == 'admin') {
      return const AdminDashboardScreen();
    }
    if (isAdminRoute) {
      if (resource == 'collections') {
        final parts = Uri.parse(screenId).pathSegments;
        return CollectionModerationScreen(
          id: parts.length == 3 ? parts[2] : null,
        );
      }
      return AdminResourceScreen(
        resource: resource == 'content' ? 'dictionary' : resource,
        review: resource == 'content',
      );
    }
    if (screenId == 'staff') {
      return const AdminDashboardScreen();
    }
    if (screenId == '/notifications' || screenId == '/study-reminder') {
      final page = screenId == '/notifications'
          ? const NotificationsScreen()
          : const StudyReminderScreen();
      return auth.user?.isGuest == true
          ? GuestAccessGate(permanentOnly: true, child: page)
          : page;
    }
    if (screenId.startsWith('/staff/')) {
      return StaffWorkspaceScreen(path: screenId);
    }
    if (screenId.startsWith('/learn')) {
      final uri = Uri.parse(screenId);
      if (uri.path == '/learn/insights') return const LearningInsightsScreen();
      if (uri.path == '/learn/history') {
        return LearningHistoryScreen(entryId: uri.queryParameters['entryId']);
      }
      if (uri.pathSegments.length == 3 && uri.pathSegments[1] == 'quiz') {
        return ReviewQuizScreen(quizId: uri.pathSegments[2]);
      }
      if (uri.pathSegments.length == 3 && uri.pathSegments[1] == 'topic') {
        return TopicLearningScreen(
          topicId: uri.pathSegments[2],
          study: uri.queryParameters['study'] == '1',
        );
      }
      if (uri.path == '/learn' && uri.queryParameters['tab'] == '2') {
        return const SignCollectionsScreen();
      }
      return LearningHub(
        initialTab: (int.tryParse(uri.queryParameters['tab'] ?? '') ?? 0).clamp(
          0,
          2,
        ),
      );
    }
    if (screenId == '/dictionary/browse') return const DictionaryScreen();
    if (screenId.startsWith('/dictionary/')) {
      return SignDetailScreen(
        entryId: Uri.decodeComponent(screenId.split('/').last),
      );
    }
    if (screenId.startsWith('/conversations/')) {
      final child = HistoryDetailScreen(id: screenId.split('/').last);
      return auth.user?.isGuest == true
          ? GuestAccessGate(permanentOnly: true, child: child)
          : child;
    }
    final page = screenFor(screenId);
    return page;
  }
}

Widget screenFor(String id) => switch (id) {
  '/communicate' => const CommunicationHub(),
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
  'S22' => const LearningHub(),
  'S23' => const SignDetailScreen(),
  'S24' => const DictionaryScreen(favoritesOnly: true),
  'S25' => const ProfileScreen(),
  'S26' => const EditProfileScreen(),
  'change-password' => const ChangePasswordScreen(),
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
