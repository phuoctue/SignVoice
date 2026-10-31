import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/google_sign_in_native.dart';
import '../../services/api/api_exception.dart';

import '../../core/navigation.dart';
import '../../core/app_route.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../../services/auth/collection_return_route.dart';
import 'web_auth_layout.dart';
import 'web_landing_page.dart';

export 'web_landing_page.dart';

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) return 'Vui lòng nhập email.';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
    return 'Email không đúng định dạng.';
  }
  return null;
}

String? validatePassword(String? value) =>
    value == null || value.length < 8 ? 'Mật khẩu cần ít nhất 8 ký tự.' : null;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  AuthProvider? auth;
  bool scheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AuthProvider>();
    if (!identical(auth, provider)) {
      auth?.removeListener(_restoreSession);
      auth = provider;
      auth!.addListener(_restoreSession);
    }
    _restoreSession();
  }

  void _restoreSession() {
    if (!mounted ||
        scheduled ||
        auth!.isLoading ||
        auth!.state == AuthState.initial) {
      return;
    }
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scheduled = false;
      if (!auth!.isLoading && auth!.state != AuthState.initial) {
        final webRoute =
            kIsWeb ||
            GoRouter.maybeOf(context) != null ||
            MediaQuery.sizeOf(context).width >= 900;
        if (auth!.isAuthenticated) {
          openRoot(context, 'S08');
        } else if (!webRoute) {
          openRoot(context, 'S02');
        } else {
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    auth?.removeListener(_restoreSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readyUnauth =
        auth != null &&
        !auth!.isLoading &&
        auth!.state != AuthState.initial &&
        !auth!.isAuthenticated;
    final webRoute =
        kIsWeb ||
        GoRouter.maybeOf(context) != null ||
        MediaQuery.sizeOf(context).width >= 900;
    if (readyUnauth && webRoute) {
      return const WebLandingPage();
    }
    return Scaffold(
    body: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.blue, Color(0xFF1D4ED8), Color(0xFF1E40AF)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Logo(size: 80, white: true),
                const SizedBox(height: 20),
                const Text(
                  'SignVoice',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Kết nối giao tiếp, xóa nhòa khoảng cách',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFBFDBFE), fontSize: 14),
                ),
                const SizedBox(height: 40),
                const SizedBox(
                  width: 180,
                  child: LinearProgressIndicator(
                    color: Colors.white,
                    backgroundColor: Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext context) {
    final webRoute =
        kIsWeb ||
        GoRouter.maybeOf(context) != null ||
        MediaQuery.sizeOf(context).width >= 900;
    if (index == 0 && webRoute) {
      return const WebLandingPage();
    }
    const titles = [
      'Biến ký hiệu thành lời nói',
      'Lắng nghe bằng văn bản',
      'Khám phá ngôn ngữ ký hiệu',
    ];
    const descriptions = [
      'Dùng camera để nhận diện ký hiệu tay và chuyển thành văn bản hoặc giọng nói.',
      'Chuyển giọng nói tiếng Việt thành văn bản lớn, dễ đọc — giúp người khiếm thính tham gia hội thoại.',
      'Từ điển tương tác với hướng dẫn từng ký hiệu giao tiếp cơ bản hàng ngày.',
    ];
    const icons = [
      Icons.back_hand_outlined,
      Icons.mic_none,
      Icons.menu_book_outlined,
    ];
    const colors = [AppColors.blue, AppColors.teal, AppColors.purple];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => openRoot(context, 'S05'),
                child: const Text('Bỏ qua'),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 218,
                            height: 218,
                            decoration: BoxDecoration(
                              color: colors[index].withAlpha(18),
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 136,
                                  height: 136,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: colors[index],
                                      width: 2,
                                    ),
                                    color: colors[index].withAlpha(14),
                                  ),
                                ),
                                Icon(
                                  icons[index],
                                  size: 76,
                                  color: colors[index],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Heading(titles[index], size: 26, center: true),
                          const SizedBox(height: 16),
                          BodyText(descriptions[index], center: true),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              3,
                              (i) => Container(
                                width: i == index ? 26 : 10,
                                height: 10,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: i == index
                                      ? AppColors.blue
                                      : Colors.blueGrey.withAlpha(70),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (index > 0) ...[
                    Expanded(
                      child: AppButton(
                        'Quay lại',
                        outlined: true,
                        onPressed: () => openScreen(
                          context,
                          'S0${index + 1}',
                          replace: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: AppButton(
                      index == 2 ? 'Bắt đầu' : 'Tiếp tục',
                      onPressed: () => index == 2
                          ? openRoot(context, 'S05')
                          : openScreen(
                              context,
                              'S0${index + 3}',
                              replace: true,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.register = false, this.returnRoute});
  final String? returnRoute;
  final bool register;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool registering = widget.register;
  Map<String, bool>? oauth;
  String? oauthError;
  @override
  void initState() {
    super.initState();
    loadOAuth();
  }

  Future<void> loadOAuth() async {
    try {
      final value = await context.read<AuthProvider>().oauthProviders();
      if (mounted) {
        setState(() {
          oauth = value;
          oauthError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => oauthError = 'Không tải được trạng thái Google/Facebook. Đăng nhập email vẫn khả dụng.',
        );
      }
    }
  }

  Future<void> socialLogin(String provider) async {
    if (busy) return;
    if (registering && !accepted) {
      toast(context, 'Vui lòng đồng ý với điều khoản để tiếp tục.');
      return;
    }
    if (!kIsWeb) {
      if (provider == 'google' && NativeGoogleSignIn.supported) {
        setState(() => busy = true);
        final auth = context.read<AuthProvider>();
        try {
          final ok = await auth.loginWithGoogle();
          if (!mounted) return;
          if (ok) {
            finishLogin();
          } else {
            toast(context, auth.errorMessage ?? 'Không đăng nhập được Google.');
          }
        } finally {
          if (mounted) setState(() => busy = false);
        }
        return;
      }
      toast(
        context,
        'OAuth hiện hỗ trợ trên web. Vui lòng đăng nhập email trong ứng dụng.',
      );
      return;
    }
    if (oauth?[provider] != true) {
      toast(
        context,
        oauthError ??
            'Đăng nhập bằng ${provider == 'google' ? 'Google' : 'Facebook'} hiện chưa sẵn sàng. Vui lòng chọn email hoặc dùng thử.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      saveCollectionReturnRoute(widget.returnRoute);
      await context.read<AuthProvider>().startOAuth(provider);
    } catch (_) {
      if (mounted) {
        toast(context, 'Không mở được trang đăng nhập. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  final _loginForm = GlobalKey<FormState>();
  final _registerForm = GlobalKey<FormState>();
  GlobalKey<FormState> get form => registering ? _registerForm : _loginForm;
  void finishLogin() {
    consumeCollectionReturnRoute();
    final target = widget.returnRoute;
    final route = target == null
        ? null
        : AppRoute.parse(
            target,
            adminResources: const [
              'users',
              'roles',
              'sessions',
              'dictionary',
              'categories',
              'collections',
              'content',
            ],
          );
    openRoot(context, route?.known == true ? target! : 'S08');
  }

  final email = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController();
  final repeatPassword = TextEditingController();
  bool hidePassword = true, hideRepeat = true, accepted = true, busy = false;
  @override
  void dispose() {
    for (final c in [email, password, name, repeatPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!form.currentState!.validate()) return;
    if (registering && !accepted) {
      toast(context, 'Vui lòng đồng ý với điều khoản để tiếp tục.');
      return;
    }
    setState(() => busy = true);
    final auth = context.read<AuthProvider>();
    final creatingAccount = registering;
    final success = registering
        ? auth.user?.isGuest == true
              ? await auth.convertGuest(
                  email: email.text.trim(),
                  password: password.text,
                  displayName: name.text.trim(),
                )
              : await auth.register(
                  email: email.text.trim(),
                  password: password.text,
                  displayName: name.text.trim(),
                )
        : await auth.login(email: email.text.trim(), password: password.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (success) {
      if (creatingAccount) {
        password.clear();
        repeatPassword.clear();
        setState(() => registering = false);
        toast(context, 'Tạo tài khoản thành công. Hãy đăng nhập để tiếp tục.');
      } else {
        finishLogin();
      }
    } else {
      toast(
        context,
        auth.errorMessage ?? 'Không thể đăng nhập. Vui lòng thử lại.',
      );
    }
  }

  Future<void> enterGuest() async {
    if (busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 520),
        scrollable: true,
        title: const Text('Dùng thử SignVoice trong 10 phút'),
        content: const Text(
          'Bạn có thể trải nghiệm giao tiếp và học ký hiệu trong 10 phút kể từ khi xác nhận. Thời gian vẫn chạy khi đổi trang hoặc tải lại. Các chức năng lưu hội thoại, yêu thích và bộ riêng cần đăng nhập. Hết giờ, bạn vẫn xem được từ điển công khai.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Vào dùng thử'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() => busy = true);
    final auth = context.read<AuthProvider>();
    final success = await auth.loginAsGuest();
    if (!mounted) return;
    setState(() => busy = false);
    if (success) {
      finishLogin();
    } else {
      toast(context, auth.errorMessage ?? 'Không thể bắt đầu dùng thử.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = kIsWeb && MediaQuery.sizeOf(context).width >= 900;
    final formContent = Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!registering) ...[
            if (!desktop) ...[
              const Center(child: Logo(size: 58)),
              const SizedBox(height: 18),
            ],
            if (desktop) ...[
              const Center(child: Logo(size: 42)),
              const SizedBox(height: 16),
              const Heading(
                'Tiếp tục hành trình\ncùng SignVoice',
                center: true,
                size: 28,
              ),
              const SizedBox(height: 10),
              const BodyText(
                'Đăng nhập để tiếp tục học và giao tiếp bằng ngôn ngữ ký hiệu.',
                center: true,
              ),
            ] else
              const Heading('Đăng nhập SignVoice', center: true),
            if (!desktop) ...[
              const SizedBox(height: 6),
              const BodyText('Tiếp tục kết nối cùng SignVoice.', center: true),
            ],
            const SizedBox(height: 24),
          ] else ...[
            if (desktop) ...[
              const Heading('Tạo tài khoản', center: true),
              const SizedBox(height: 20),
            ],
          ],
          if (desktop && !registering) ...[
            WebSocialSignIn(
              busy: busy,
              onGoogle: () => socialLogin('google'),
              onFacebook: () => socialLogin('facebook'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'hoặc dùng email',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 20),
          ],
          if (registering) ...[
            _field(
              'Họ và tên',
              TextFormField(
                controller: name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Nguyễn Văn A'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Vui lòng nhập họ và tên.'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _field(
            'Email',
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(hintText: 'email@example.com'),
              validator: validateEmail,
            ),
          ),
          const SizedBox(height: 16),
          _field(
            'Mật khẩu',
            TextFormField(
              controller: password,
              obscureText: hidePassword,
              textInputAction: registering
                  ? TextInputAction.next
                  : TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!registering && !busy) submit();
              },
              decoration: InputDecoration(
                hintText: 'Tối thiểu 8 ký tự',
                suffixIcon: IconButton(
                  tooltip: hidePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  onPressed: () => setState(() => hidePassword = !hidePassword),
                  icon: Icon(
                    hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                final error = validatePassword(value);
                if (error != null || !registering) return error;
                if (!RegExp(r'[a-zA-Z]').hasMatch(value!) ||
                    !RegExp(r'[0-9]').hasMatch(value)) {
                  return 'Mật khẩu cần có chữ cái và số.';
                }
                return null;
              },
            ),
          ),
          if (registering) ...[
            const SizedBox(height: 16),
            _field(
              'Xác nhận mật khẩu',
              TextFormField(
                controller: repeatPassword,
                obscureText: hideRepeat,
                decoration: InputDecoration(
                  hintText: 'Nhập lại mật khẩu',
                  suffixIcon: IconButton(
                    tooltip: hideRepeat
                        ? 'Hiện mật khẩu xác nhận'
                        : 'Ẩn mật khẩu xác nhận',
                    onPressed: () => setState(() => hideRepeat = !hideRepeat),
                    icon: Icon(
                      hideRepeat
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) => v != password.text
                    ? 'Mật khẩu xác nhận không khớp.'
                    : validatePassword(v),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: accepted,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const BodyText(
                'Tôi đồng ý với Điều khoản dịch vụ và Chính sách quyền riêng tư.',
              ),
              onChanged: (v) => setState(() => accepted = v ?? false),
            ),
          ] else
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => openScreen(context, 'S07'),
                child: const Text('Quên mật khẩu?'),
              ),
            ),
          const SizedBox(height: 12),
          AppButton(
            registering ? 'Tạo tài khoản' : 'Đăng nhập',
            fill: true,
            key: const ValueKey('auth-submit'),
            busy: busy,
            onPressed: submit,
          ),
          if (!desktop && !registering) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'hoặc',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),
            AppButton(
              'Tiếp tục với Google',
              outlined: true,
              icon: Icons.account_circle_outlined,
              onPressed: busy ? null : () => socialLogin('google'),
            ),
            const SizedBox(height: 12),
            AppButton(
              'Tiếp tục với Facebook',
              outlined: true,
              icon: Icons.facebook,
              onPressed: busy ? null : () => socialLogin('facebook'),
            ),
          ],
          if (!registering) ...[
            const SizedBox(height: 18),
            if (!desktop)
              TextButton(
                onPressed: busy
                    ? null
                    : () => widget.returnRoute == null
                          ? openScreen(context, 'S06')
                          : Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => AuthScreen(
                                  register: true,
                                  returnRoute: widget.returnRoute,
                                ),
                              ),
                            ),
                child: const Text('Chưa có tài khoản? Đăng ký'),
              ),
            if (desktop)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: busy ? null : enterGuest,
                    icon: const Icon(Icons.explore_outlined, size: 18),
                    label: const Text('Khám phá bản dùng thử'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : () => openRoot(context, 'S01'),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('Giới thiệu SignVoice'),
                  ),
                ],
              )
            else
              TextButton(
                onPressed: busy ? null : enterGuest,
                child: const Text('Dùng thử không cần tài khoản'),
              ),
          ],
        ],
      ),
    );
    if (desktop) {
      return WebAuthLayout(
        register: registering,
        form: formContent,
        busy: busy,
        onSwitch: () {
          if (!busy) setState(() => registering = !registering);
        },
      );
    }
    return AppPage(
      title: registering ? 'Tạo tài khoản' : 'Đăng nhập',
      showBack: registering || widget.returnRoute != null,
      child: formContent,
    );
  }

  Widget _field(String label, Widget input) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      input,
    ],
  );
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.authService});
  final AuthService? authService;
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  bool sent = false;
  bool busy = false;
  String? error;

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await (widget.authService ?? AuthService.instance).requestPasswordReset(
        email.text,
      );
      if (mounted) setState(() => sent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Không thể gửi yêu cầu. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Quên mật khẩu',
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 36),
          Icon(
            sent ? Icons.check_circle_outline : Icons.lock_outline,
            size: 72,
            color: sent ? AppColors.green : AppColors.blue,
          ),
          const SizedBox(height: 24),
          Heading(
            sent ? 'Kiểm tra email của bạn' : 'Khôi phục tài khoản',
            center: true,
          ),
          const SizedBox(height: 14),
          BodyText(
            sent
                ? 'Nếu email này có tài khoản, bạn sẽ nhận được liên kết đặt lại mật khẩu. Kiểm tra cả thư rác. Liên kết hết hạn sau 15 phút.'
                : 'Nhập email của bạn để yêu cầu liên kết đặt lại mật khẩu.',
            center: true,
          ),
          const SizedBox(height: 28),
          if (!sent) ...[
            TextFormField(
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'email@example.com',
              ),
              validator: validateEmail,
            ),
            const SizedBox(height: 18),
            AppButton(
              busy ? 'Đang gửi...' : 'Gửi yêu cầu',
              onPressed: busy ? null : submit,
            ),
            const SizedBox(height: 18),
            if (error != null) Notice(error!),
          ] else
            AppButton(
              'Quay lại đăng nhập',
              onPressed: () => openRoot(context, 'S05'),
            ),
        ],
      ),
    ),
  );
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.token, this.authService});
  final String token;
  final AuthService? authService;
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;
  bool done = false;
  bool hidePassword = true;
  String? error;

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await (widget.authService ?? AuthService.instance).resetPassword(
        token: widget.token,
        newPassword: password.text,
      );
      password.clear();
      confirmation.clear();
      if (mounted) setState(() => done = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Không thể đổi mật khẩu. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final validToken = RegExp(r'^[a-f0-9]{64}$').hasMatch(widget.token);
    return AppPage(
      title: 'Đặt lại mật khẩu',
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 36),
            Icon(
              done ? Icons.check_circle_outline : Icons.lock_reset,
              size: 72,
              color: done ? AppColors.green : AppColors.blue,
            ),
            const SizedBox(height: 24),
            Heading(
              done ? 'Đã đổi mật khẩu' : 'Tạo mật khẩu mới',
              center: true,
            ),
            const SizedBox(height: 18),
            if (done) ...[
              const BodyText(
                'Các phiên đăng nhập cũ đã được thu hồi. Hãy đăng nhập bằng mật khẩu mới.',
                center: true,
              ),
              const SizedBox(height: 24),
              AppButton(
                'Quay lại đăng nhập',
                onPressed: () => openRoot(context, 'S05'),
              ),
            ] else if (!validToken) ...[
              const Notice(
                'Liên kết không hợp lệ. Vui lòng yêu cầu liên kết mới.',
              ),
              const SizedBox(height: 24),
              AppButton(
                'Yêu cầu liên kết mới',
                onPressed: () => openRoot(context, 'S07'),
              ),
            ] else ...[
              const BodyText(
                'Mật khẩu cần 8–128 ký tự, có ít nhất một chữ cái và một chữ số.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: password,
                enabled: !busy,
                obscureText: hidePassword,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Mật khẩu mới',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => hidePassword = !hidePassword),
                    icon: Icon(
                      hidePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                validator: (value) {
                  final short = validatePassword(value);
                  if (short != null) return short;
                  if (value!.length > 128) return 'Mật khẩu tối đa 128 ký tự.';
                  if (!RegExp(r'[a-zA-Z]').hasMatch(value) ||
                      !RegExp(r'[0-9]').hasMatch(value)) {
                    return 'Mật khẩu cần có chữ cái và chữ số.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: confirmation,
                enabled: !busy,
                obscureText: hidePassword,
                decoration: const InputDecoration(
                  labelText: 'Nhập lại mật khẩu mới',
                ),
                validator: (value) =>
                    value == password.text && value != null && value.isNotEmpty
                    ? null
                    : 'Mật khẩu nhập lại không khớp.',
              ),
              const SizedBox(height: 24),
              if (error != null) ...[
                Notice(error!),
                const SizedBox(height: 18),
              ],
              AppButton(
                busy ? 'Đang lưu...' : 'Lưu mật khẩu mới',
                onPressed: busy ? null : submit,
              ),
              TextButton(
                onPressed: busy ? null : () => openRoot(context, 'S07'),
                child: const Text('Yêu cầu liên kết mới'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
