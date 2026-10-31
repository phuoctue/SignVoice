import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'web_account_menu.dart';

import '../core/navigation.dart';
import '../providers/auth_provider.dart';

class WebWorkspaceScope extends InheritedWidget {
  const WebWorkspaceScope({super.key, required super.child});
  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WebWorkspaceScope>() != null;
  @override
  bool updateShouldNotify(WebWorkspaceScope oldWidget) => false;
}

/// Match semantic destinations; unrelated query parameters do not change selection.
bool webDestinationSelected(Uri current, String destination) {
  final path = current.path, target = Uri.parse(destination);
  if (destination == '/learn?tab=2') {
    return path == '/learn' && current.queryParameters['tab'] == '2' ||
        path.startsWith('/collections/') && path != '/collections/discover';
  }
  if (destination == '/learn') {
    return path == '/learn' && current.queryParameters['tab'] != '2' ||
        path.startsWith('/learn/topic/') ||
        path.startsWith('/learn/quiz/');
  }
  if (destination == '/dictionary') {
    return path == '/dictionary' ||
        path.startsWith('/dictionary/') ||
        path.startsWith('/learn') ||
        path.startsWith('/collections') ||
        path == '/favorites';
  }
  if (destination == '/communicate') {
    return const {
          '/communicate',
          '/sign-to-speech',
          '/speech-to-sign',
        }.contains(path) ||
        const {
          'S09',
          'S10',
          'S11',
          'S12',
          'S13',
          'S14',
          'S15',
          'S16',
          'S17',
          'S18',
          'S19',
        }.contains(legacyLocation(path));
  }
  if (destination == '/admin') {
    return path == '/admin' ||
        path.startsWith('/admin/') ||
        path.startsWith('/staff');
  }
  if (destination == '/profile') {
    return path == '/profile' ||
        path.startsWith('/profile/') ||
        path == '/study-reminder' ||
        path == '/notifications';
  }
  if (destination == '/history') {
    return path == '/history' || path.startsWith('/conversations/');
  }
  return path == target.path;
}

class WebWorkspace extends StatefulWidget {
  const WebWorkspace({super.key, required this.child, this.uri});
  final Widget child;
  final Uri? uri;
  @override
  State<WebWorkspace> createState() => _WebWorkspaceState();
}

class _WebWorkspaceState extends State<WebWorkspace> {
  bool expanded = false;
  final menuScroll = ScrollController();
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(
          () => expanded = prefs.getBool('web_sidebar_expanded') ?? false,
        );
      }
    });
  }

  Future<void> toggle() async {
    setState(() => expanded = !expanded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('web_sidebar_expanded', expanded);
  }

  @override
  void dispose() {
    menuScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uri =
        widget.uri ??
        GoRouter.maybeOf(context)?.routerDelegate.currentConfiguration.uri ??
        Uri.parse(webLocation(ModalRoute.of(context)?.settings.name ?? 'S08'));
    final scheme = Theme.of(context).colorScheme;
    final entries = <(String, IconData, String)>[
      ('/dashboard', Icons.dashboard_outlined, 'Tổng quan'),
      ('/communicate', Icons.forum_outlined, 'Giao tiếp'),
      ('/dictionary', Icons.menu_book_outlined, 'Thư viện ký hiệu'),
      ('/history', Icons.history, 'Hội thoại'),
      if (auth.isStaff)
        ('/admin', Icons.admin_panel_settings_outlined, 'Quản trị'),
    ];
    Widget entry(String path, IconData icon, String label) {
      final selected = webDestinationSelected(uri, path);
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: expanded ? 224 : 56,
            child: Tooltip(
              message: expanded ? '' : label,
              child: Semantics(
                selected: selected,
                child: Material(
                  color: selected
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (uri.toString() != path) openRoot(context, path);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            size: 24,
                            color: selected
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                          if (expanded) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final navigation = Material(
      color: scheme.surface,
      child: ClipRect(
        child: AnimatedContainer(
          key: const ValueKey('web-sidebar'),
          width: expanded ? 248 : 80,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 248,
            maxWidth: 248,
            child: SizedBox(
              width: 248,
              child: SafeArea(
                child: Column(
                  children: [
                    SizedBox(
                      height: 64,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Icon(
                              Icons.sign_language,
                              color: scheme.primary,
                              size: 28,
                            ),
                          ),
                          if (expanded)
                            Expanded(
                              child: Text(
                                'SignVoice',
                                maxLines: 1,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: scheme.primary,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Scrollbar(
                        controller: menuScroll,
                        child: ListView(
                          controller: menuScroll,
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final (path, icon, label) in entries)
                              entry(path, icon, label),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: expanded ? 248 : 80,
                        height: 52,
                        child: Tooltip(
                          message: expanded
                              ? 'Thu gọn thanh điều hướng'
                              : 'Mở thanh điều hướng',
                          child: TextButton(
                            onPressed: toggle,
                            child: Semantics(
                              label: expanded
                                  ? 'Thu gọn thanh điều hướng'
                                  : 'Mở thanh điều hướng',
                              excludeSemantics: true,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    expanded
                                        ? Icons.chevron_left
                                        : Icons.chevron_right,
                                  ),
                                  if (expanded)
                                    const Flexible(child: Text('Thu gọn')),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: expanded ? 248 : 80,
                        child: WebAccountMenu(
                          sidebar: true,
                          expanded: expanded,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return WebWorkspaceScope(
      child: Row(
        children: [
          navigation,
          VerticalDivider(width: 1, color: scheme.outlineVariant),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
