import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/navigation.dart';
import '../core/app_state.dart';
import '../providers/auth_provider.dart';
import 'ui.dart';
import 'web_account_menu.dart';

/// Public navigation never offers private destinations as if they were public.
class PublicCatalogPage extends StatelessWidget {
  const PublicCatalogPage({
    super.key,
    required this.child,
    required this.title,
    this.current = 'dictionary',
    this.scroll = true,
  });
  final Widget child;
  final String title, current;
  final bool scroll;
  @override
  Widget build(BuildContext context) => Title(
    title: '$title · SignVoice',
    color: Theme.of(context).colorScheme.primary,
    child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: PublicHeaderContent(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final wide =
                        box.maxWidth >= 1100 &&
                        MediaQuery.textScalerOf(context).scale(1) < 1.5;
                    final auth = context.watch<AuthProvider>();
                    final state = context
                        .dependOnInheritedWidgetOfExactType<AppScope>()
                        ?.notifier;
                    final dark =
                        Theme.of(context).brightness == Brightness.dark;
                    return Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        PublicHeaderBrand(
                          onPressed: () => openRoot(context, 'S01'),
                        ),
                        if (wide)
                          Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                onPressed: () => openRoot(context, 'S22'),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                child: const Text('Từ điển ký hiệu'),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                ),
                                onPressed: () =>
                                    openRoot(context, '/collections/discover'),
                                child: const Text('Bộ sưu tập công khai'),
                              ),
                            ],
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (!wide)
                              PopupMenuButton<String>(
                                tooltip: 'Điều hướng công khai',
                                icon: const Icon(Icons.menu),
                                onSelected: (path) => openRoot(context, path),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'S01',
                                    child: Text('Trang giới thiệu'),
                                  ),
                                  PopupMenuItem(
                                    value: 'S22',
                                    child: Text('Từ điển ký hiệu'),
                                  ),
                                  PopupMenuItem(
                                    value: '/collections/discover',
                                    child: Text('Bộ sưu tập công khai'),
                                  ),
                                ],
                              ),
                            if (state != null) ...[
                              IconButton(
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                tooltip: dark
                                    ? 'Chuyển sang giao diện sáng'
                                    : 'Chuyển sang giao diện tối',
                                onPressed: () => state.update(
                                  () => state.themeMode = dark
                                      ? ThemeMode.light
                                      : ThemeMode.dark,
                                ),
                                icon: Icon(
                                  dark
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                ),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(
                                  minWidth: 48,
                                  minHeight: 48,
                                ),
                                tooltip: state.highContrast
                                    ? 'Tắt tương phản cao'
                                    : 'Bật tương phản cao',
                                onPressed: () => state.update(
                                  () =>
                                      state.highContrast = !state.highContrast,
                                ),
                                icon: const Icon(Icons.contrast),
                              ),
                            ],
                            if (auth.isAuthenticated) ...[
                              TextButton(
                                onPressed: () => openRoot(context, '/learn'),
                                child: const Text('Không gian học'),
                              ),
                              const WebAccountMenu(),
                            ] else ...[
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: () => openRoot(context, 'S05'),
                                child: const Text('Đăng nhập'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: () => openRoot(context, 'S06'),
                                child: const Text('Đăng ký'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: !scroll
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1304),
                        child: child,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.all(
                        MediaQuery.sizeOf(context).width < 600 ? 20 : 32,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1240),
                          child: child,
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

/// Shared width and gutters keep public navigation aligned with page content.
class PublicHeaderContent extends StatelessWidget {
  const PublicHeaderContent({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 600 ? 20 : 32,
      vertical: 12,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

class PublicHeaderBrand extends StatelessWidget {
  const PublicHeaderBrand({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: EdgeInsets.zero,
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Logo(size: 34),
        SizedBox(width: 10),
        Flexible(
          child: Text(
            'SignVoice',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}
