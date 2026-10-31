import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../widgets/public_sign_preview.dart';
import '../../widgets/public_catalog_page.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../../services/api/api_config.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import 'landing_hero_demo.dart';
import 'landing_library_preview.dart';
import 'landing_motion.dart';
import 'landing_sections.dart';

class WebLandingPage extends StatefulWidget {
  const WebLandingPage({super.key});
  @override
  State<WebLandingPage> createState() => _WebLandingPageState();
}

class _WebLandingPageState extends State<WebLandingPage> {
  final _scroll = ScrollController();
  final _featuresKey = GlobalKey(),
      _stepsKey = GlobalKey(),
      _libraryKey = GlobalKey(),
      _faqKey = GlobalKey();
  bool _startingGuest = false,
      _started = false,
      _loading = true,
      _reduceMotion = false;
  bool _scrolled = false, _statsVisible = false;
  int _section = -1;
  int? _wordCount, _categoryCount, _collectionCount;
  String? _error;
  List<AdminRecord> _words = [], _heroWords = [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loadPublicData();
    }
  }

  Future<void> _loadPublicData() async {
    final dictionary = context.read<AdminWorkspaceService?>();
    final learning = context.read<LearningService?>();
    if (dictionary == null) {
      _loading = false;
      _error = 'Thư viện chưa sẵn sàng. Hãy mở từ điển công khai.';
      return;
    }
    // Each public source can fail independently without hiding the other counts.
    await Future.wait<void>([
      () async {
        try {
          final page = await dictionary.published();
          if (mounted) {
            setState(() {
              _wordCount = page.total;
              _loading = false;
            });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = 'Chưa tải được thư viện. Bạn có thể thử tra cứu lại bên dưới.';
            });
          }
        }
      }(),
      () async {
        try {
          final words = await dictionary.featuredEntries();
          if (mounted) setState(() => _words = words);
        } catch (_) {
          /* No fabricated featured samples. */
        }
      }(),
      () async {
        try {
          final samples = await dictionary.published(search: 'chào');
          final greetings = samples.items
              .where(
                (word) => const [
                  'chào',
                  'xin chào',
                ].contains('${word['word']}'.toLowerCase()),
              )
              .toList();
          if (mounted) setState(() => _heroWords = greetings);
        } catch (_) {
          /* The initial public page remains a usable preview. */
        }
      }(),
      () async {
        try {
          final categories = await dictionary.activeCategories();
          if (mounted) setState(() => _categoryCount = categories.length);
        } catch (_) {
          /* Unknown counts stay unavailable, never zero. */
        }
      }(),
      if (learning != null)
        () async {
          try {
            final data = await learning.collectionRead('/shared-collections');
            final total = (data['pagination'] as Map?)?['total'];
            if (mounted && total is num) {
              setState(() => _collectionCount = total.toInt());
            }
          } catch (_) {
            /* Public collection availability does not block lookup. */
          }
        }(),
    ]);
  }

  void _onScroll() {
    if (!mounted) return;
    final scrolled = _scroll.hasClients && _scroll.offset > 12;
    var section = -1;
    final keys = [_featuresKey, _stepsKey, _libraryKey, _faqKey];
    for (var i = 0; i < keys.length; i++) {
      final box = keys[i].currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          box.localToGlobal(Offset.zero).dy <
              MediaQuery.sizeOf(context).height * .45) {
        section = i;
      }
    }
    if (_scrolled != scrolled || _section != section) {
      setState(() {
        _scrolled = scrolled;
        _section = section;
      });
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: _reduceMotion || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _startTrial({String destination = 'S08'}) async {
    if (_startingGuest) return;
    final auth = context.read<AuthProvider?>();
    if (auth == null) {
      openRoot(context, 'S05');
      return;
    }
    if (auth.isAuthenticated) {
      openRoot(context, destination);
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      animationStyle: _reduceMotion || MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (dialogContext) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 520),
        scrollable: true,
        title: const Text('Dùng thử SignVoice trong 10 phút'),
        content: const Text(
          'Bạn có thể trải nghiệm giao tiếp và học ký hiệu trong 10 phút kể từ khi xác nhận. '
          'Các chức năng lưu hội thoại, yêu thích và bộ riêng cần đăng nhập. '
          'Hết giờ, bạn vẫn xem được từ điển công khai.',
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
    setState(() => _startingGuest = true);
    final success = await auth.loginAsGuest();
    if (!mounted) return;
    setState(() => _startingGuest = false);
    if (success) {
      openRoot(context, 'S08');
    } else {
      toast(context, auth.errorMessage ?? 'Không thể bắt đầu dùng thử.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: media.disableAnimations || _reduceMotion,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          materialTapTargetSize: MaterialTapTargetSize.padded,
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: const StadiumBorder(),
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          chipTheme: Theme.of(context).chipTheme.copyWith(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
        ),
        child: Builder(
          builder: (context) {
            final state = context
                .dependOnInheritedWidgetOfExactType<AppScope>()
                ?.notifier;
            return Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    _header(context, state),
                    Expanded(
                      child: Scrollbar(
                        controller: _scroll,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding: EdgeInsets.symmetric(
                            horizontal: media.size.width < 600 ? 20 : 32,
                            vertical: 36,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1240),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  LandingBackdrop(
                                    scroll: _scroll,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 32,
                                        horizontal: 0,
                                      ),
                                      child: _hero(context),
                                    ),
                                  ),
                                  const SizedBox(height: 44),
                                  LandingReveal(
                                    scroll: _scroll,
                                    onVisible: () {
                                      if (mounted && !_statsVisible) {
                                        setState(() => _statsVisible = true);
                                      }
                                    },
                                    child: _stats(context),
                                  ),
                                  const SizedBox(height: 88),
                                  KeyedSubtree(
                                    key: _featuresKey,
                                    child: _sections(context).features(context),
                                  ),
                                  const SizedBox(height: 88),
                                  KeyedSubtree(
                                    key: _stepsKey,
                                    child: _sections(context).steps(context),
                                  ),
                                  const SizedBox(height: 88),
                                  KeyedSubtree(
                                    key: _libraryKey,
                                    child: LandingReveal(
                                      scroll: _scroll,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _sectionHeading(
                                            context,
                                            'Chạm để khám phá',
                                            'Một từ mới. Một cách kết nối mới.',
                                            'Tra ngay một từ tiếng Việt và xem mẫu ký hiệu từ thư viện công khai.',
                                          ),
                                          const SizedBox(height: 24),
                                          LandingLibraryPreview(
                                            words: _words,
                                            loading: _loading,
                                            error: _error,
                                          ),
                                          const SizedBox(height: 16),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                              onPressed: () => openRoot(
                                                context,
                                                '/dictionary/browse',
                                              ),
                                              icon: const Icon(
                                                Icons.arrow_forward,
                                              ),
                                              label: const Text(
                                                'Mở toàn bộ từ điển',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 88),
                                  LandingReveal(
                                    scroll: _scroll,
                                    child: KeyedSubtree(
                                      key: _faqKey,
                                      child: _sections(context).faq(context),
                                    ),
                                  ),
                                  const SizedBox(height: 64),
                                  LandingReveal(
                                    scroll: _scroll,
                                    child: _bottomCta(context),
                                  ),

                                  const SizedBox(height: 56),
                                  LandingReveal(
                                    scroll: _scroll,
                                    child: _footer(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _bottomCta(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bắt đầu từ một lời chào.',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Tạo tài khoản để lưu hội thoại, bộ từ riêng và tiến trình học của bạn.',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            LandingCta(
              label: 'Tạo tài khoản miễn phí',
              onPressed: () => openRoot(context, 'S06'),
            ),
            OutlinedButton.icon(
              onPressed: () => _startTrial(),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Dùng thử 10 phút'),
            ),
          ],
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.secondaryContainer],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          if (_heroWords.isEmpty ||
              box.maxWidth < 800 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4) {
            return copy;
          }
          return Row(
            children: [
              Expanded(flex: 3, child: copy),
              const SizedBox(width: 32),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: PublicSignPreview(
                    word: _heroWords.first,
                    height: 220,
                    controls: false,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, AppState? state) {
    final scheme = Theme.of(context).colorScheme,
        dark = Theme.of(context).brightness == Brightness.dark;
    final wide =
        MediaQuery.sizeOf(context).width >= 1100 &&
        MediaQuery.textScalerOf(context).scale(1) < 1.4;
    final systemReduce = MediaQuery.disableAnimationsOf(this.context),
        reduced = systemReduce || _reduceMotion;
    final items = [
      (0, 'Tính năng', _featuresKey),
      (1, 'Cách hoạt động', _stepsKey),
      (2, 'Từ điển ký hiệu', _libraryKey),
      (3, 'Câu hỏi thường gặp', _faqKey),
    ];
    void top() {
      if (reduced) {
        _scroll.jumpTo(0);
        return;
      }
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    }

    return AnimatedPhysicalModel(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      shape: BoxShape.rectangle,
      elevation: _scrolled ? 5 : 0,
      shadowColor: scheme.shadow.withAlpha(45),
      color: scheme.surface,
      child: PublicHeaderContent(
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            PublicHeaderBrand(onPressed: top),
            if (wide)
              Wrap(
                spacing: 2,
                children: [
                  for (final (i, label, key) in items)
                    TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: _section == i
                            ? scheme.primaryContainer
                            : null,
                      ),
                      onPressed: () => _scrollTo(key),
                      child: Text(label),
                    ),
                ],
              )
            else
              PopupMenuButton<int>(
                tooltip: 'Mở menu giới thiệu',
                icon: const Icon(Icons.menu),
                onSelected: (i) {
                  if (i == 4) {
                    if (state != null) {
                      state.update(
                        () => state.highContrast = !state.highContrast,
                      );
                    }
                  } else {
                    _scrollTo(items[i].$3);
                  }
                },
                itemBuilder: (_) => [
                  for (final (i, label, _) in items)
                    PopupMenuItem(value: i, child: Text(label)),
                  if (state != null)
                    CheckedPopupMenuItem(
                      value: 4,
                      checked: state.highContrast,
                      child: const Text('Tương phản cao'),
                    ),
                ],
              ),
            Wrap(
              spacing: 4,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (state != null)
                  IconButton(
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
                if (state != null && wide)
                  IconButton(
                    tooltip: state.highContrast
                        ? 'Tắt tương phản cao'
                        : 'Bật tương phản cao',
                    onPressed: () => state.update(
                      () => state.highContrast = !state.highContrast,
                    ),
                    icon: const Icon(Icons.contrast),
                  ),
                IconButton(
                  tooltip: systemReduce
                      ? 'Giảm chuyển động theo hệ thống'
                      : _reduceMotion
                      ? 'Bật chuyển động'
                      : 'Giảm chuyển động',
                  isSelected: reduced,
                  selectedIcon: const Icon(Icons.motion_photos_off),
                  onPressed: systemReduce
                      ? null
                      : () => setState(() => _reduceMotion = !_reduceMotion),
                  icon: const Icon(Icons.animation),
                ),
                OutlinedButton(
                  onPressed: () => openRoot(context, 'S05'),
                  child: const Text('Đăng nhập'),
                ),
                FilledButton(
                  onPressed: () => openRoot(context, 'S06'),
                  child: const Text('Đăng ký'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final wide =
            box.maxWidth >= 920 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.5;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LandingReveal(
              scroll: _scroll,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Ngôn ngữ ký hiệu · Kết nối mỗi ngày'.toUpperCase(),
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontSize: 12,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            LandingReveal(
              scroll: _scroll,
              delay: 90,
              child: LandingHeadline(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Kết nối giao tiếp,\n'),
                      TextSpan(
                        text: 'xóa nhòa khoảng cách.',
                        style: TextStyle(color: scheme.primary),
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontSize: wide ? 58 : 40,
                    height: 1.28,
                    letterSpacing: -.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            LandingReveal(
              scroll: _scroll,
              delay: 180,
              child: Text(
                'Học bằng hình ảnh. Giao tiếp bằng ký hiệu và lời nói. Từng bước mở ra những cuộc trò chuyện gần gũi hơn.',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(height: 1.6),
              ),
            ),
            const SizedBox(height: 28),
            LandingReveal(
              scroll: _scroll,
              delay: 270,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  LandingCta(
                    key: const ValueKey('landing-primary-cta'),
                    label: 'Bắt đầu học miễn phí',
                    onPressed: () {
                      openRoot(context, 'S06');
                    },
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('landing-guest-cta'),
                    onPressed: _startingGuest
                        ? null
                        : () {
                            _startTrial();
                          },
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text(
                      _startingGuest ? 'Đang mở…' : 'Dùng thử 10 phút',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(180, 54),
                      shape: const StadiumBorder(),
                      backgroundColor: scheme.surface.withAlpha(
                        landingHighContrast(context) ? 255 : 180,
                      ),
                      side: BorderSide(color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              key: const ValueKey('landing-dictionary-cta'),
              onPressed: () => openRoot(context, '/dictionary/browse'),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Khám phá từ điển công khai'),
            ),
            const SizedBox(height: 10),
            Text(
              'Camera & microphone chỉ bật khi bạn cho phép.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
        final demo = LandingReveal(
          scroll: _scroll,
          delay: 180,
          child: LandingHeroDemo(words: _heroWords, loading: _loading),
        );
        final tools = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 11, child: copy),
                  const SizedBox(width: 48),
                  Expanded(flex: 10, child: demo),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [copy, const SizedBox(height: 32), demo],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                box.maxWidth < 600 ? 20 : 36,
                48,
                box.maxWidth < 600 ? 20 : 36,
                12,
              ),
              child: tools,
            ),
          ],
        );
      },
    );
  }

  Widget _stats(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: landingGlass(context),
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow =
              box.maxWidth < 550 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          final cells = [
            for (final (count, label) in [
              (_wordCount, 'ký hiệu công khai'),
              (_categoryCount, 'chủ đề khám phá'),
              (_collectionCount, 'bộ sưu tập công khai'),
            ])
              SizedBox(
                width: narrow ? box.maxWidth : (box.maxWidth - 32) / 3,
                child: Column(
                  crossAxisAlignment: narrow
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: _statsVisible ? (count ?? 0).toDouble() : 0,
                      ),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 800),
                      builder: (_, value, _) => Text(
                        count == null
                            ? '—'
                            : NumberFormat.decimalPattern('vi')
                                  .format(value.round()),
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 48,
                              height: 1.3,
                              color: scheme.primary,
                            ),
                      ),
                    ),
                    Text(label),
                  ],
                ),
              ),
          ];
          return Wrap(spacing: 16, runSpacing: 24, children: cells);
        },
      ),
    );
  }

  Widget _sectionHeading(
    BuildContext context,
    String eyebrow,
    String title,
    String subtitle,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 2.2,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 12),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Text(
          subtitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.5),
        ),
      ),
    ],
  );

  LandingSections _sections(BuildContext context) => LandingSections(
    scroll: _scroll,
    onTrial: () => _startTrial(destination: '/sign-to-speech'),
    onSpeech: () => _startTrial(destination: '/speech-to-sign'),
    onRegister: () => openRoot(context, 'S06'),
    onLibrary: () => _scrollTo(_libraryKey),
  );

  Widget _footer(BuildContext context) {
    final available =
        (MediaQuery.sizeOf(context).width -
                (MediaQuery.sizeOf(context).width < 600 ? 40 : 64))
            .clamp(0.0, 1240.0);
    final columns =
        MediaQuery.textScalerOf(context).scale(1) >= 1.5 || available < 560
        ? 1
        : available < 940
        ? 2
        : 4;
    final footerColumnWidth = (available - 32 * (columns - 1)) / columns;
    Widget column(String title, List<Widget> links) => SizedBox(
      width: footerColumnWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...links,
        ],
      ),
    );
    Widget link(String title, VoidCallback action) => TextButton(
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.zero,
        minimumSize: const Size(48, 48),
      ),
      onPressed: action,
      child: Text(title),
    );
    Future<void> policy(String path) async {
      final ok = await launchUrl(
        Uri.base.resolve(ApiConfig.baseUrl).resolve(path),
      );
      if (!ok && mounted) {
        toast(this.context, 'Chưa thể mở trang. Vui lòng thử lại.');
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 28),
        Wrap(
          spacing: 32,
          runSpacing: 28,
          children: [
            column('SignVoice', [
              const Text(
                'Kết nối bằng ngôn ngữ ký hiệu.\nHọc mỗi ngày, gần nhau hơn.',
                style: TextStyle(height: 1.6),
              ),
            ]),
            column('Sản phẩm', [
              link(
                'Từ điển công khai',
                () => openRoot(context, '/dictionary/browse'),
              ),
              link(
                'Bộ sưu tập công khai',
                () => openRoot(context, '/collections/discover'),
              ),
              link('Dùng thử 10 phút', _startTrial),
            ]),
            column('Hỗ trợ', [
              link('Cách bắt đầu', () => _scrollTo(_stepsKey)),
              link('Đăng nhập', () => openRoot(context, 'S05')),
              link('Liên hệ hỗ trợ', () => policy('/privacy')),
              link('Tạo tài khoản', () => openRoot(context, 'S06')),
            ]),
            column('Quyền riêng tư', [
              link('Chính sách quyền riêng tư', () => policy('/privacy')),
              link('Yêu cầu xóa dữ liệu', () => policy('/data-deletion')),
            ]),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          '© ${DateTime.now().year} SignVoice. Kết nối bằng ngôn ngữ ký hiệu.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
