import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Slides within a single route, retaining the form's controllers and values.
class WebAuthLayout extends StatefulWidget {
  const WebAuthLayout({
    super.key,
    required this.register,
    required this.form,
    required this.onSwitch,
    required this.busy,
  });
  final bool register, busy;
  final Widget form;
  final VoidCallback onSwitch;
  @override
  State<WebAuthLayout> createState() => _WebAuthLayoutState();
}

class _WebAuthLayoutState extends State<WebAuthLayout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
    duration: const Duration(milliseconds: 650),
    value: widget.register ? 1 : 0,
  )..addListener(_frame);
  late Widget _form;
  late bool _formRegister;
  bool _reduceMotion = false;
  @override
  void initState() {
    super.initState();
    _form = widget.form;
    _formRegister = widget.register;
  }

  void _frame() {
    final side = _animation.value >= .5;
    if (side == widget.register && side != _formRegister) {
      _formRegister = side;
      _form = widget.form;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant WebAuthLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.register != widget.register) {
      if (_reduceMotion) {
        _formRegister = widget.register;
        _form = widget.form;
        _animation.value = widget.register ? 1 : 0;
      } else {
        _animation.animateTo(
          widget.register ? 1 : 0,
          curve: Curves.easeInOutCubic,
        );
      }
    } else if (_formRegister == widget.register) {
      _form = widget.form;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _animation.value;
    final moving = _animation.isAnimating;
    return Scaffold(
      floatingActionButton: IconButton.filledTonal(
        tooltip: _reduceMotion ? 'Bật hiệu ứng trượt' : 'Giảm chuyển động',
        icon: Icon(
          _reduceMotion ? Icons.motion_photos_off_outlined : Icons.animation,
        ),
        onPressed: () {
          setState(() => _reduceMotion = !_reduceMotion);
          if (_reduceMotion) {
            _formRegister = widget.register;
            _form = widget.form;
            _animation.value = widget.register ? 1 : 0;
          }
        },
      ),
      body: LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (viewport.maxHeight - 64).clamp(0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Material(
                  color: theme.colorScheme.surface,
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.circular(28),
                  child: LayoutBuilder(
                    builder: (context, card) {
                      final half = card.maxWidth / 2;
                      return Stack(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: half,
                                  child: Transform.translate(
                                    offset: Offset(half * t, 0),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 800,
                                      ),
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 36,
                                            vertical: 32,
                                          ),
                                          child: IgnorePointer(
                                            ignoring: moving,
                                            child: ExcludeFocus(
                                              excluding: moving,
                                              child: ExcludeSemantics(
                                                excluding: moving,
                                                child: Opacity(
                                                  opacity:
                                                      (((t - .5).abs() - .12) /
                                                              .38)
                                                          .clamp(0, 1),
                                                  child: Theme(
                                                    data: theme.copyWith(
                                                      inputDecorationTheme: theme
                                                          .inputDecorationTheme
                                                          .copyWith(
                                                            contentPadding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      16,
                                                                  vertical: 13,
                                                                ),
                                                          ),
                                                    ),
                                                    child: AutofillGroup(
                                                      child: _form,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: half,
                                  child: ExcludeSemantics(
                                    child: ExcludeFocus(
                                      child: IgnorePointer(
                                        child: Opacity(
                                          opacity: 0,
                                          child: _panel(t >= .5, null),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment(1 - 2 * t, 0),
                              child: SizedBox(
                                width: half,
                                height: double.infinity,
                                child: DecoratedBox(
                                  key: const ValueKey('auth-sliding-panel'),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.blue,
                                        Color(0xFF1E40AF),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.horizontal(
                                      left: Radius.circular(100 * (1 - t)),
                                      right: Radius.circular(100 * t),
                                    ),
                                  ),
                                  child: _panel(
                                    t >= .5,
                                    widget.busy
                                        ? null
                                        : () {
                                            FocusManager.instance.primaryFocus
                                                ?.unfocus();
                                            widget.onSwitch();
                                          },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(bool register, VoidCallback? onSwitch) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.sign_language_outlined, size: 56, color: Colors.white),
        const SizedBox(height: 20),
        const Text(
          'SignVoice',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          register ? 'Chào mừng trở lại!' : 'Kết nối không khoảng cách',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          register
              ? 'Đăng nhập để tiếp tục hành trình của bạn.'
              : 'Cùng khám phá ngôn ngữ ký hiệu.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            height: 1.6,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton(
          onPressed: onSwitch,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white70),
            minimumSize: const Size(180, 48),
          ),
          child: Text(register ? 'Tôi đã có tài khoản' : 'Tạo tài khoản mới'),
        ),
      ],
    ),
  );
}

class WebSocialSignIn extends StatelessWidget {
  const WebSocialSignIn({
    super.key,
    required this.busy,
    required this.onGoogle,
    required this.onFacebook,
  });
  final bool busy;
  final VoidCallback onGoogle, onFacebook;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _button(
        context,
        'Tiếp tục với Google',
        const SizedBox(
          width: 24,
          height: 24,
          child: CustomPaint(painter: _GoogleMarkPainter()),
        ),
        onGoogle,
      ),
      const SizedBox(width: 16),
      _button(
        context,
        'Tiếp tục với Facebook',
        const Icon(Icons.facebook, size: 26),
        onFacebook,
      ),
    ],
  );
  Widget _button(
    BuildContext context,
    String label,
    Widget icon,
    VoidCallback action,
  ) => IconButton.outlined(
    tooltip: label,
    onPressed: busy ? null : action,
    style: IconButton.styleFrom(
      minimumSize: const Size(52, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      foregroundColor: Theme.of(context).colorScheme.primary,
    ),
    icon: icon,
  );
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(21.6, 12.23)
        ..cubicTo(21.6, 11.52, 21.54, 10.84, 21.42, 10.18)
        ..lineTo(12, 10.18)
        ..lineTo(12, 14.05)
        ..lineTo(17.38, 14.05)
        ..cubicTo(17.15, 15.3, 16.44, 16.36, 15.38, 17.07)
        ..lineTo(15.38, 19.58)
        ..lineTo(18.62, 19.58)
        ..cubicTo(20.51, 17.84, 21.6, 15.27, 21.6, 12.23)
        ..close(),
      paint..color = const Color(0xFF4285F4),
    );
    canvas.drawPath(
      Path()
        ..moveTo(12, 22)
        ..cubicTo(14.7, 22, 16.96, 21.1, 18.62, 19.58)
        ..lineTo(15.38, 17.07)
        ..cubicTo(14.49, 17.67, 13.35, 18.02, 12, 18.02)
        ..cubicTo(9.4, 18.02, 7.19, 16.26, 6.4, 13.89)
        ..lineTo(3.05, 13.89)
        ..lineTo(3.05, 16.48)
        ..cubicTo(4.7, 19.76, 8.09, 22, 12, 22)
        ..close(),
      paint..color = const Color(0xFF34A853),
    );
    canvas.drawPath(
      Path()
        ..moveTo(6.4, 13.89)
        ..cubicTo(6.2, 13.29, 6.09, 12.65, 6.09, 12)
        ..cubicTo(6.09, 11.35, 6.2, 10.71, 6.4, 10.11)
        ..lineTo(6.4, 7.52)
        ..lineTo(3.05, 7.52)
        ..cubicTo(2.38, 8.87, 2, 10.39, 2, 12)
        ..cubicTo(2, 13.61, 2.38, 15.13, 3.05, 16.48)
        ..close(),
      paint..color = const Color(0xFFFBBC05),
    );
    canvas.drawPath(
      Path()
        ..moveTo(12, 5.98)
        ..cubicTo(13.47, 5.98, 14.79, 6.49, 15.82, 7.49)
        ..lineTo(18.69, 4.62)
        ..cubicTo(16.96, 3.01, 14.7, 2, 12, 2)
        ..cubicTo(8.09, 2, 4.7, 4.24, 3.05, 7.52)
        ..lineTo(6.4, 10.11)
        ..cubicTo(7.19, 7.74, 9.4, 5.98, 12, 5.98)
        ..close(),
      paint..color = const Color(0xFFEA4335),
    );
  }

  @override
  bool shouldRepaint(_GoogleMarkPainter oldDelegate) => false;
}
