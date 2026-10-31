import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';

bool landingHighContrast(BuildContext context) =>
    MediaQuery.highContrastOf(context) ||
    (context
            .dependOnInheritedWidgetOfExactType<AppScope>()
            ?.notifier
            ?.highContrast ??
        false);

/// Finite split-panel reveal. Only panel transforms rebuild during animation;
/// the live media stays in a separate repaint boundary.
class LandingPortal extends StatefulWidget {
  const LandingPortal({
    super.key,
    required this.child,
    this.scroll,
    this.signal,
    this.hero = false,
  });
  final Widget child;
  final ScrollController? scroll;
  final ValueListenable<int>? signal;
  final bool hero;
  @override
  State<LandingPortal> createState() => _LandingPortalState();
}

class _LandingPortalState extends State<LandingPortal>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    animationBehavior: AnimationBehavior.preserve,
  );
  bool reduced = false, requested = false, foreground = true;
  @override
  void initState() {
    super.initState();
    widget.scroll?.addListener(onScroll);
    widget.signal?.addListener(open);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(LandingPortal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scroll != widget.scroll) {
      oldWidget.scroll?.removeListener(onScroll);
      widget.scroll?.addListener(onScroll);
    }
    if (oldWidget.signal != widget.signal) {
      oldWidget.signal?.removeListener(open);
      widget.signal?.addListener(open);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      controller.value = 1;
    } else if (requested && foreground && controller.value < 1) {
      controller.forward();
    }
  }

  void onScroll() {
    final scroll = widget.scroll;
    if (!mounted || scroll == null || !scroll.hasClients) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final visible =
        top < MediaQuery.sizeOf(context).height * .9 &&
        top + box.size.height > 80;
    if (!visible) {
      if (controller.isAnimating) controller.value = 1;
      return;
    }
    final threshold = MediaQuery.sizeOf(context).width < 600 ? 28 : 60;
    if (scroll.offset > threshold) open();
  }

  void open() {
    requested = true;
    if (reduced) {
      controller.value = 1;
    } else if (foreground && !controller.isAnimating && controller.value < 1) {
      controller.forward();
    }
  }

  void replay() {
    if (reduced) return;
    requested = false;
    controller.reverse();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      controller.stop();
    } else if (requested && !reduced && controller.value < 1) {
      controller.forward();
    }
  }

  @override
  void dispose() {
    widget.scroll?.removeListener(onScroll);
    widget.signal?.removeListener(open);
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final contrast = landingHighContrast(context);
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return MouseRegion(
      onEnter: (_) {
        if (!mobile) open();
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.hero ? 32 : 22),
        child: LayoutBuilder(
          builder: (context, box) => AnimatedBuilder(
            animation: controller,
            child: RepaintBoundary(child: widget.child),
            builder: (context, media) {
              final progress = Curves.easeInOutCubic.transform(
                controller.value,
              );
              Widget panel(bool left) => Transform.translate(
                key: ValueKey(
                  left ? 'portal-panel-left' : 'portal-panel-right',
                ),
                offset: Offset(
                  (left ? -1 : 1) * box.maxWidth * .51 * progress,
                  0,
                ),
                child: Align(
                  alignment: left
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: .5,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        gradient: contrast
                            ? null
                            : LinearGradient(
                                begin: left
                                    ? Alignment.topLeft
                                    : Alignment.bottomRight,
                                end: left
                                    ? Alignment.bottomRight
                                    : Alignment.topLeft,
                                colors: [
                                  scheme.surface,
                                  scheme.primaryContainer,
                                ],
                              ),
                        border: Border.all(
                          color: contrast
                              ? scheme.onSurface
                              : scheme.primary.withAlpha(160),
                          width: contrast ? 2 : 1,
                        ),
                      ),
                      child: !widget.hero
                          ? null
                          : Align(
                              alignment: left
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    left ? 'Sign' : 'Voice',
                                    style: TextStyle(
                                      fontSize: mobile ? 56 : 120,
                                      height: 1.35,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              );
              return Semantics(
                label: 'Khung ký hiệu',
                value: progress == 1
                    ? 'Đã mở'
                    : progress == 0
                    ? 'Đã đóng'
                    : 'Đang mở',
                child: Stack(
                  children: [
                    ExcludeFocus(
                      excluding: progress < 1,
                      child: ExcludeSemantics(
                        excluding: progress < 1,
                        child: media,
                      ),
                    ),
                    if (progress < 1)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: Stack(children: [panel(true), panel(false)]),
                          ),
                        ),
                      ),
                    if (progress < 1)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: requested,
                          child: ExcludeFocus(
                            excluding: requested,
                            child: ExcludeSemantics(
                              excluding: requested,
                              child: Opacity(
                                opacity: (1 - progress * 3).clamp(0.0, 1.0),
                                child: Align(
                                  alignment: widget.hero
                                      ? Alignment.bottomCenter
                                      : Alignment.center,
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: FilledButton.icon(
                                      key: const ValueKey('portal-open'),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(48, 48),
                                        padding: const EdgeInsets.all(16),
                                      ),
                                      onPressed: open,
                                      icon: const Icon(Icons.open_in_full),
                                      label: Text(
                                        widget.hero
                                            ? 'Khám phá SignVoice'
                                            : 'Mở khung ký hiệu',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (widget.hero && progress == 1 && !reduced)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: FilledButton.tonalIcon(
                          onPressed: replay,
                          icon: const Icon(Icons.replay),
                          label: const Text('Xem lại portal'),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class LandingReveal extends StatefulWidget {
  const LandingReveal({
    super.key,
    required this.scroll,
    required this.child,
    this.delay = 0,
    this.revealBuilder,
    this.onVisible,
  });
  final ScrollController scroll;
  final Widget child;
  final int delay;
  final VoidCallback? onVisible;
  final Widget Function(BuildContext, double, Widget?)? revealBuilder;
  @override
  State<LandingReveal> createState() => _LandingRevealState();
}

class _LandingRevealState extends State<LandingReveal>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 560 + widget.delay),
  );
  late final progress = CurvedAnimation(
    parent: controller,
    curve: Interval(
      widget.delay / (560 + widget.delay),
      1,
      curve: Curves.easeOutCubic,
    ),
  );
  bool revealed = false;
  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(check);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (!revealed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onVisible?.call();
        });
      }
      revealed = true;
      controller.value = 1;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  void check() {
    if (!mounted || revealed) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < MediaQuery.sizeOf(context).height * .97 &&
        top + box.size.height > 0) {
      revealed = true;
      widget.onVisible?.call();
      controller.forward();
    }
  }

  @override
  void dispose() {
    widget.scroll.removeListener(check);
    progress.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (context, child) => ExcludeFocus(
      excluding: progress.value == 0,
      child: ExcludeSemantics(
        excluding: progress.value == 0,
        child: FadeTransition(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - progress.value)),
            child:
                widget.revealBuilder?.call(context, progress.value, child) ??
                child,
          ),
        ),
      ),
    ),
  );
}

class LandingHover extends StatefulWidget {
  const LandingHover({super.key, required this.child, required this.color});
  final Widget child;
  final Color color;
  @override
  State<LandingHover> createState() => _LandingHoverState();
}

class _LandingHoverState extends State<LandingHover> {
  bool active = false;
  final reflection = ValueNotifier<Alignment>(Alignment.topLeft);
  @override
  void dispose() {
    reflection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (focused) => setState(() => active = focused),
    child: MouseRegion(
      onHover: (event) {
        if (MediaQuery.disableAnimationsOf(context) ||
            landingHighContrast(context)) {
          return;
        }
        final box = context.findRenderObject();
        if (box is RenderBox && box.hasSize) {
          reflection.value = Alignment(
            (event.localPosition.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0),
            (event.localPosition.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0),
          );
        }
      },
      onEnter: (_) => setState(() => active = true),
      onExit: (_) => setState(() => active = false),
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(
          0,
          active && !MediaQuery.disableAnimationsOf(context) ? -4 : 0,
          0,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: widget.color.withAlpha(
                active && !landingHighContrast(context) ? 40 : 0,
              ),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ValueListenableBuilder<Alignment>(
                    valueListenable: reflection,
                    builder: (context, alignment, _) => DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient:
                            active &&
                                !landingHighContrast(context) &&
                                !MediaQuery.disableAnimationsOf(context)
                            ? RadialGradient(
                                center: alignment,
                                radius: 1.1,
                                colors: [
                                  widget.color.withAlpha(18),
                                  Colors.transparent,
                                ],
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LandingCta extends StatefulWidget {
  const LandingCta({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;
  @override
  State<LandingCta> createState() => _LandingCtaState();
}

class _LandingCtaState extends State<LandingCta> {
  bool hover = false, pressed = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final scheme = Theme.of(context).colorScheme;
    final contrast = landingHighContrast(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() {
        hover = false;
        pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => pressed = true),
        onPointerUp: (_) => setState(() => pressed = false),
        onPointerCancel: (_) => setState(() => pressed = false),
        child: AnimatedScale(
          scale: reduce
              ? 1
              : pressed
              ? .97
              : hover
              ? 1.02
              : 1,
          duration: duration,
          child: AnimatedContainer(
            duration: duration,
            transform: Matrix4.translationValues(
              0,
              hover && !reduce ? -4 : 0,
              0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: contrast
                  ? null
                  : LinearGradient(colors: [AppColors.blue, AppColors.purple]),
              color: contrast ? scheme.primary : null,
              border: Border.all(
                color: focused ? scheme.onSurface : scheme.primary,
                width: focused ? 3 : 1,
              ),
              boxShadow: contrast
                  ? []
                  : [
                      BoxShadow(
                        color: AppColors.blue.withAlpha(hover ? 90 : 30),
                        blurRadius: hover ? 32 : 16,
                      ),
                    ],
            ),
            child: FilledButton(
              onFocusChange: (value) => setState(() => focused = value),
              onPressed: widget.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: contrast ? scheme.onPrimary : Colors.white,
                shadowColor: Colors.transparent,
                shape: const StadiumBorder(),
                minimumSize: const Size(210, 54),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 14),
                  AnimatedSlide(
                    offset: Offset(hover && !reduce ? .2 : 0, 0),
                    duration: duration,
                    child: const Icon(Icons.arrow_forward, size: 20),
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

class LandingBackdrop extends StatefulWidget {
  const LandingBackdrop({super.key, required this.child, required this.scroll});
  final Widget child;
  final ScrollController scroll;
  @override
  State<LandingBackdrop> createState() => _LandingBackdropState();
}

class _LandingBackdropState extends State<LandingBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(check);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        landingHighContrast(context)) {
      controller.stop();
      controller.value = .5;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  void check() {
    if (!mounted) return;
    final box = context.findRenderObject();
    final visible =
        box is RenderBox &&
        box.hasSize &&
        box.localToGlobal(Offset.zero).dy + box.size.height > 80 &&
        box.localToGlobal(Offset.zero).dy < MediaQuery.sizeOf(context).height;
    final animate =
        visible &&
        foreground &&
        !MediaQuery.disableAnimationsOf(context) &&
        !landingHighContrast(context);
    if (animate && !controller.isAnimating) controller.repeat(reverse: true);
    if (!animate) controller.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    check();
  }

  @override
  void dispose() {
    widget.scroll.removeListener(check);
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, widget.scroll]),
    child: RepaintBoundary(child: widget.child),
    builder: (context, child) => ClipRect(
      child: CustomPaint(
        painter: _BackdropPainter(
          Theme.of(context).colorScheme.primary,
          controller.value,
          MediaQuery.disableAnimationsOf(context)
              ? 0
              : ((widget.scroll.hasClients ? widget.scroll.offset : 0) * -.15)
                    .clamp(-72.0, 0.0),
          landingHighContrast(context),
        ),
        child: child,
      ),
    ),
  );
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.color, this.progress, this.parallax, this.contrast);
  final Color color;
  final double progress, parallax;
  final bool contrast;
  @override
  void paint(Canvas canvas, Size size) {
    if (contrast) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final (x, y, tint, alpha) in [
      (.8, .25, color, 55),
      (.45, .6, AppColors.purple, 34),
      (.1, .85, AppColors.teal, 22),
    ]) {
      final center = Offset(
        size.width * (x + .04 * progress),
        size.height * y + parallax,
      );
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader =
              RadialGradient(colors: [tint.withAlpha(alpha), tint.withAlpha(0)])
                  .createShader(
                    Rect.fromCircle(
                      center: center,
                      radius: size.shortestSide * .85,
                    ),
                  ),
      );
    }
    final dots = Paint()..color = color.withAlpha(18);
    for (double x = 12; x < size.width; x += 32) {
      for (double y = 12; y < size.height; y += 32) {
        canvas.drawCircle(Offset(x, y), .8, dots);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.color != color ||
      old.progress != progress ||
      old.parallax != parallax ||
      old.contrast != contrast;
}

BoxDecoration landingGlass(BuildContext context, {Color? accent}) {
  final scheme = Theme.of(context).colorScheme;
  final contrast = landingHighContrast(context);
  final dark = scheme.brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(32),
    color: contrast ? scheme.surface : null,
    gradient: contrast
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                (accent ?? scheme.primary).withAlpha(dark ? 28 : 12),
                scheme.surface.withAlpha(dark ? 205 : 245),
              ),
              scheme.surface.withAlpha(dark ? 150 : 235),
            ],
          ),
    border: Border.all(
      color: contrast ? scheme.onSurface : scheme.outlineVariant.withAlpha(130),
      width: contrast ? 2 : 1,
    ),
    boxShadow: contrast
        ? []
        : [
            BoxShadow(
              color: (accent ?? scheme.primary).withAlpha(dark ? 18 : 10),
              blurRadius: 32,
            ),
          ],
  );
}

class LandingHeadline extends StatelessWidget {
  const LandingHeadline({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (landingHighContrast(context)) return child;
    final dark = scheme.brightness == Brightness.dark;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 1800),
      child: child,
      builder: (context, progress, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-1 + progress * .4, -.5),
          end: Alignment(1, .5),
          colors: dark
              ? [
                  AppColors.canvas,
                  scheme.primary,
                  AppColors.canvas,
                  const Color(0xFFC4B5FD),
                  AppColors.canvas,
                ]
              : [
                  AppColors.ink,
                  AppColors.blue,
                  AppColors.ink,
                  AppColors.purple,
                  AppColors.ink,
                ],
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}
