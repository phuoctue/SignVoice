import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Presentation tokens from design/quiz-reference/sign_language_matching_quiz.html.
class QuizGamePalette {
  QuizGamePalette(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get background =>
      dark ? const Color(0xFF111426) : const Color(0xFFF0F4FF);
  Color get backgroundEnd =>
      dark ? const Color(0xFF21182D) : const Color(0xFFFEF7FF);
  Color get surface => dark ? const Color(0xFF22263B) : Colors.white;
  Color get ink => dark ? const Color(0xFFF1F3FF) : const Color(0xFF1E293B);
  Color get muted => dark ? const Color(0xFFB9C2DC) : const Color(0xFF64748B);
  Color get primary => dark ? const Color(0xFFB3BCFF) : const Color(0xFF4F46E5);
  Color get violet => dark ? const Color(0xFFC6AAFF) : const Color(0xFF7C3AED);
  Color get pink => dark ? const Color(0xFFF5ABD6) : const Color(0xFFDB2777);
  Color get soft => dark ? const Color(0xFF303551) : const Color(0xFFEEF2FF);
  Color get line => dark ? const Color(0xFF48506D) : const Color(0xFFE0E7FF);
  Color get success => dark ? const Color(0xFF8EE2BE) : const Color(0xFF047857);
  Color get successSurface =>
      dark ? const Color(0xFF1D3E36) : const Color(0xFFECFDF5);
  Color get amber => dark ? const Color(0xFFFCD38B) : const Color(0xFFB45309);
  Color get amberSurface =>
      dark ? const Color(0xFF403321) : const Color(0xFFFFF7ED);
  LinearGradient get gradient => LinearGradient(colors: [primary, violet]);
  ThemeData theme(ThemeData base) => base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'PlusJakartaSans',
      bodyColor: ink,
      displayColor: ink,
    ),
    colorScheme: base.colorScheme.copyWith(
      primary: primary,
      onPrimary: dark ? const Color(0xFF1D2040) : Colors.white,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      primaryContainer: soft,
      outlineVariant: line,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: line),
        textStyle: const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: line),
    ),
  );
}

class QuizGlassPanel extends StatelessWidget {
  const QuizGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 24,
    this.highlight = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final p = QuizGamePalette(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: highlight ? p.primary.withValues(alpha: .45) : p.line,
        ),
        boxShadow: [
          BoxShadow(
            color: (p.dark ? Colors.black : const Color(0xFF6366F1)).withValues(
              alpha: p.dark ? .16 : .09,
            ),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class QuizGradientTitle extends StatelessWidget {
  const QuizGradientTitle(this.text, {super.key, this.size = 24});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = QuizGamePalette(context);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          LinearGradient(colors: [p.primary, p.violet, p.pink])
              .createShader(bounds),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      ),
    );
  }
}

class QuizGradientButton extends StatelessWidget {
  const QuizGradientButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.busy = false,
    this.icon = Icons.arrow_forward_rounded,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final p = QuizGamePalette(context), enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? p.gradient : null,
        color: enabled ? null : p.soft,
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: p.primary.withValues(alpha: .2),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: p.dark ? const Color(0xFF17203A) : Colors.white,
          disabledForegroundColor: p.muted,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, size: 20),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class QuizDashedBorder extends CustomPainter {
  QuizDashedBorder(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(16),
        ).deflate(1),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 11) {
        canvas.drawPath(
          metric.extractPath(offset, math.min(offset + 6, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(QuizDashedBorder oldDelegate) =>
      oldDelegate.color != color;
}

class QuizCelebration extends StatefulWidget {
  const QuizCelebration({super.key});
  @override
  State<QuizCelebration> createState() => _QuizCelebrationState();
}

class _QuizCelebrationState extends State<QuizCelebration>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      if (!MediaQuery.disableAnimationsOf(context)) controller.forward();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        painter: _ConfettiPainter(controller.value, QuizGamePalette(context)),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress, this.palette);
  final double progress;
  final QuizGamePalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final colors = [
      palette.primary,
      palette.violet,
      palette.pink,
      palette.success,
      palette.amber,
    ];
    for (var i = 0; i < 32; i++) {
      final angle = (i / 32) * math.pi * 2,
          distance = progress * (70 + (i % 5) * 22);
      final x = size.width / 2 + math.cos(angle) * distance,
          y = 82 + math.sin(angle) * distance + 100 * progress * progress;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * (i % 7));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3, -5, 6, 10),
          const Radius.circular(2),
        ),
        Paint()
          ..color = colors[i % colors.length].withValues(alpha: 1 - progress),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
