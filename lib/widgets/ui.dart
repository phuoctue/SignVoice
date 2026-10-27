import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

import '../core/navigation.dart';
import '../core/theme.dart';

class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    required this.child,
    this.showBack = true,
    this.actions,
    this.footer,
    this.tabIndex,
    this.scroll = true,
    this.padding = const EdgeInsets.all(20),
  });
  final String title;
  final Widget child;
  final bool showBack, scroll;
  final List<Widget>? actions;
  final Widget? footer;
  final int? tabIndex;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              tooltip: 'Quay lại',
              onPressed: () => backOrHome(context),
              icon: const Icon(Icons.chevron_left),
            )
          : null,
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: scroll
                ? SingleChildScrollView(padding: padding, child: child)
                : Padding(padding: padding, child: child),
          ),
          if (footer != null && tabIndex != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: footer!,
            ),
        ],
      ),
    ),
    // Keep transient snackbars above a fixed action instead of covering it.
    bottomNavigationBar: tabIndex != null
        ? AppNavigationBar(selectedIndex: tabIndex!)
        : footer == null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: footer!,
            ),
          ),
  );
}

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({super.key, required this.selectedIndex});
  final int selectedIndex;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManage = auth.isStaff;
    final screens = ['S08', 'S22', 'S20', 'S25', if (canManage) 'admin'];
    return NavigationBar(
      selectedIndex: selectedIndex < screens.length ? selectedIndex : 3,
      onDestinationSelected: (index) {
        if (index != selectedIndex) {
          openRoot(context, screens[index]);
        }
      },
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Trang chủ',
        ),
        const NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: 'Từ điển',
        ),
        const NavigationDestination(
          icon: Icon(Icons.history),
          label: 'Lịch sử',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Cá nhân',
        ),
        if (canManage)
          const NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: 'Quản trị',
          ),
      ],
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
    this.color,
    this.secondary = false,
    this.outlined = false,
    this.compact = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool secondary, outlined, compact, busy;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    final onColor = color == null
        ? scheme.onPrimary
        : c.computeLuminance() > .179
        ? Colors.black
        : Colors.white;
    final style = ButtonStyle(
      minimumSize: WidgetStateProperty.all(
        Size(compact ? 0 : double.infinity, compact ? 44 : 56),
      ),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? Theme.of(context).disabledColor
            : (outlined || secondary ? c : onColor),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? c.withAlpha(25)
            : (outlined
                  ? Colors.transparent
                  : secondary
                  ? c.withAlpha(22)
                  : c),
      ),
      side: outlined ? WidgetStateProperty.all(BorderSide(color: c)) : null,
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy) ...[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 19),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: style,
      child: content,
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.borderColor,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? color, borderColor;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor ?? scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class BodyText extends StatelessWidget {
  const BodyText(this.text, {super.key, this.center = false, this.color});
  final String text;
  final bool center;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : null,
    style: TextStyle(
      fontSize: 14,
      height: 1.6,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class Heading extends StatelessWidget {
  const Heading(this.text, {super.key, this.size = 22, this.center = false});
  final String text;
  final double size;
  final bool center;
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: center ? TextAlign.center : null,
    style: TextStyle(fontSize: size, height: 1.3, fontWeight: FontWeight.w800),
  );
}

class SignVoiceBadge extends StatelessWidget {
  const SignVoiceBadge(
    this.text, {
    super.key,
    this.color = AppColors.blue,
    this.icon,
  });
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withAlpha(22),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(
    this.text, {
    super.key,
    this.color = AppColors.blue,
    this.icon = Icons.info_outline,
  });
  final String text;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => AppCard(
    color: color.withAlpha(15),
    borderColor: color.withAlpha(45),
    padding: const EdgeInsets.all(14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: BodyText(text, color: Theme.of(context).colorScheme.onSurface),
        ),
      ],
    ),
  );
}

class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.color = AppColors.blue,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    onTap: onTap,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      trailing:
          trailing ??
          (onTap != null ? const Icon(Icons.chevron_right, size: 20) : null),
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.history,
    this.action,
  });
  final String title, description;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Column(
      children: [
        Icon(icon, size: 58, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 18),
        Heading(title, size: 19, center: true),
        const SizedBox(height: 10),
        BodyText(description, center: true),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.size = 48, this.white = false});
  final double size;
  final bool white;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: white ? Colors.white.withAlpha(35) : AppColors.blue.withAlpha(18),
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: CustomPaint(
      painter: _LogoPainter(white ? Colors.white : AppColors.blue),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 40, size.height / 40);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(14, 26)
        ..quadraticBezierTo(14, 21, 19, 17),
      p,
    );
    canvas.drawLine(const Offset(19, 12), const Offset(19, 22), p);
    canvas.drawLine(const Offset(23, 15), const Offset(23, 22), p);
    canvas.drawLine(const Offset(27, 17), const Offset(27, 22), p);
    canvas.drawPath(
      Path()
        ..moveTo(14, 26)
        ..quadraticBezierTo(20, 30, 25, 27),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(29, 22)
        ..quadraticBezierTo(33, 25, 31, 27),
      p,
    );
    p.strokeWidth = 1.5;
    canvas.drawPath(
      Path()
        ..moveTo(31, 28)
        ..quadraticBezierTo(34, 30, 32, 33),
      p,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => color != oldDelegate.color;
}

class PulseOrb extends StatefulWidget {
  const PulseOrb({
    super.key,
    required this.icon,
    this.color = AppColors.teal,
    this.animate = false,
    this.onTap,
    this.label,
  });
  final IconData icon;
  final Color color;
  final bool animate;
  final VoidCallback? onTap;
  final String? label;
  @override
  State<PulseOrb> createState() => _PulseOrbState();
}

class _PulseOrbState extends State<PulseOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  @override
  void initState() {
    super.initState();
    if (widget.animate) controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PulseOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) controller.repeat();
    if (!widget.animate && oldWidget.animate) controller.stop();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 210,
    width: 210,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final phase =
            widget.animate && !MediaQuery.of(context).disableAnimations
            ? controller.value
            : 0.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 125 + i * 24 + phase * 16,
                height: 125 + i * 24 + phase * 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withAlpha(14 - i * 3),
                ),
              ),
            Semantics(
              button: widget.onTap != null,
              label: widget.label,
              child: Material(
                shape: const CircleBorder(),
                color: widget.color,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onTap,
                  child: SizedBox(
                    width: 112,
                    height: 112,
                    child: Icon(widget.icon, color: Colors.white, size: 48),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class Waveform extends StatefulWidget {
  const Waveform({super.key, this.active = true, this.color = AppColors.teal});
  final bool active;
  final Color color;
  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, child) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(24, (i) {
          final t = widget.active && !MediaQuery.of(context).disableAnimations
              ? controller.value
              : 0;
          final height = 8 + (math.sin(i * .9 + t * math.pi * 2).abs() * 30);
          return Container(
            width: 5,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(5),
            ),
          );
        }),
      ),
    ),
  );
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
Future<String?> editText(
  BuildContext context, {
  required String title,
  required String initial,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, maxLines: 4, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
  // Đợi dialog hoàn tất animation trước khi huỷ controller của TextField.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ) ??
    false;
