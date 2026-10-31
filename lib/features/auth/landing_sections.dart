import 'package:flutter/material.dart';

import 'landing_motion.dart';

class LandingSections {
  const LandingSections({
    required this.scroll,
    required this.onTrial,
    required this.onRegister,
    required this.onSpeech,
    required this.onLibrary,
  });
  final ScrollController scroll;
  final VoidCallback onTrial, onRegister, onLibrary, onSpeech;
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

  Widget _feature(
    BuildContext context, {
    required String number,
    required String title,
    required String body,
    required IconData icon,
    required Widget visual,
    required String action,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return LandingHover(
      color: scheme.primary,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: landingHighContrast(context)
                ? scheme.onSurface
                : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: landingGlass(
            context,
            accent: accent ? scheme.primary : null,
          ),
          child: InkWell(
            onTap: onTap,
            focusColor: scheme.primary.withAlpha(65),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: scheme.onSurface),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: scheme.primary, size: 30),
                        const Spacer(),
                        Text(number),
                      ],
                    ),
                    const SizedBox(height: 24),
                    visual,
                    const SizedBox(height: 24),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(body, style: const TextStyle(height: 1.5)),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          action,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Icon(Icons.arrow_forward, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _productImage(BuildContext context, String asset, String label) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                'assets/landing/$asset.png',
                fit: BoxFit.contain,
                semanticLabel: label,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Giao diện sản phẩm · Dữ liệu minh họa',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
  Widget features(BuildContext context) {
    final cards = [
      _feature(
        context,
        number: '01',
        title: 'Để đôi tay cất lời.',
        body: 'Mở camera, cấp quyền khi sẵn sàng và chuyển ký hiệu thành lời nói tiếng Việt.',
        icon: Icons.sign_language_outlined,
        action: 'Mở công cụ camera',
        onTap: onTrial,
        accent: true,
        visual: _productImage(
          context,
          'camera',
          'Giao diện cấp quyền và công cụ camera SignVoice',
        ),
      ),
      _feature(
        context,
        number: '02',
        title: 'Lời nói thành hình ảnh.',
        body: 'Nói hoặc nhập tiếng Việt để tìm mẫu ký hiệu tương ứng.',
        icon: Icons.mic_none,
        action: 'Mở giọng nói & văn bản',
        onTap: onSpeech,
        visual: _productImage(
          context,
          'speech',
          'Giao diện công cụ giọng nói và văn bản SignVoice',
        ),
      ),
      _feature(
        context,
        number: '03',
        title: 'Nhìn. Nhớ. Thử lại.',
        body:
            'Xem mẫu theo chủ đề, thử nhớ nghĩa và đối chiếu trong bài ôn tập.',
        icon: Icons.menu_book_outlined,
        action: 'Tra một từ ngay',
        onTap: onLibrary,
        visual: _productImage(
          context,
          'quiz',
          'Giao diện ôn tập ký hiệu SignVoice',
        ),
      ),
      _feature(
        context,
        number: '04',
        title: 'Tiến bộ theo nhịp của bạn.',
        body: 'Theo dõi mục tiêu, lưu bộ từ riêng và đặt lịch học khi có tài khoản.',
        icon: Icons.trending_up,
        action: 'Tạo không gian học',
        onTap: onRegister,
        visual: _productImage(
          context,
          'dashboard',
          'Giao diện mục tiêu và biểu đồ tiến độ SignVoice',
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LandingReveal(
          scroll: scroll,
          child: _sectionHeading(
            context,
            'Một nơi cho cả học và giao tiếp',
            'Gần nhau hơn qua từng ký hiệu.',
            'Khám phá các công cụ trong giao diện SignVoice.',
          ),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, box) {
            final wide =
                box.maxWidth >= 900 &&
                MediaQuery.textScalerOf(context).scale(1) < 1.5;
            Widget reveal(int i) => LandingReveal(
              scroll: scroll,
              delay: i.isOdd ? 100 : 0,
              child: cards[i],
            );
            if (!wide) {
              return Column(
                children: [
                  for (var i = 0; i < 4; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: reveal(i),
                    ),
                ],
              );
            }
            Widget pair(int left, int right, int flex) => IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: flex, child: reveal(left)),
                  const SizedBox(width: 20),
                  Expanded(flex: 12 - flex, child: reveal(right)),
                ],
              ),
            );
            return Column(
              children: [
                pair(0, 1, 6),
                const SizedBox(height: 20),
                pair(2, 3, 6),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget steps(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LandingReveal(
        scroll: scroll,
        child: _sectionHeading(
          context,
          'BẮT ĐẦU THẬT NHẸ NHÀNG',
          'Ba bước cho một thói quen mới.',
          'Không cần biết ký hiệu trước. Hãy bắt đầu bằng một từ quen thuộc.',
        ),
      ),
      const SizedBox(height: 28),
      LayoutBuilder(
        builder: (context, box) {
          final columns =
              box.maxWidth >= 800 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.5
              ? 3
              : 1;
          return Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              for (final (i, title, body) in [
                (0, 'Chọn một từ', 'Tra từ hoặc khám phá chủ đề bạn quan tâm.'),
                (
                  1,
                  'Quan sát mẫu',
                  'Xem ảnh, phát video và làm quen từng động tác.',
                ),
                (
                  2,
                  'Thử nhớ lại',
                  'Dùng thử phần học hoặc tạo tài khoản để lưu tiến trình.',
                ),
              ])
                SizedBox(
                  width: (box.maxWidth - (columns - 1) * 24) / columns,
                  child: LandingReveal(
                    scroll: scroll,
                    delay: i * 100,
                    revealBuilder: (context, progress, child) => Stack(
                      children: [
                        child!,
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                height: 3,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '0${i + 1}',
                                style: TextStyle(
                                  fontSize: 32,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                [
                                  Icons.search,
                                  Icons.play_circle_outline,
                                  Icons.quiz_outlined,
                                ][i],
                                color: Theme.of(context).colorScheme.primary,
                                size: 32,
                              ),
                              if (columns == 3 && i < 2)
                                const Padding(
                                  padding: EdgeInsets.only(left: 16),
                                  child: Icon(Icons.arrow_forward, size: 20),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Text(body),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget faq(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.only(bottom: 32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.accessibility_new,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Học theo cách dễ tiếp cận với bạn',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hỗ trợ chữ lớn, tương phản cao, giảm chuyển động và điều khiển bằng bàn phím. Bạn có thể dùng các tùy chọn ở thanh đầu trang.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _sectionHeading(
        context,
        'Bạn có thể đang thắc mắc',
        'Cùng làm rõ trước khi bắt đầu.',
        'Một vài điều cần biết về thư viện, dùng thử và dữ liệu của bạn.',
      ),
      const SizedBox(height: 24),
      for (final (q, a) in [
        (
          'Tôi có cần tài khoản để xem từ điển?',
          'Không. Từ điển và mẫu ký hiệu công khai luôn có thể xem mà không cần đăng nhập.',
        ),
        (
          'Bản dùng thử 10 phút hoạt động thế nào?',
          'Thời gian bắt đầu khi bạn xác nhận dùng thử và vẫn chạy khi đổi trang hoặc tải lại. Hết giờ, bạn cần đăng nhập để tiếp tục học và giao tiếp; từ điển công khai vẫn mở.',
        ),
        (
          'Những chức năng nào cần đăng nhập?',
          'Lưu hội thoại, yêu thích, bộ từ riêng, tiến trình học và lịch học cần tài khoản để lưu và đồng bộ.',
        ),
        (
          'Trang này có tự bật camera hoặc microphone không?',
          'Không. Bạn chỉ cấp quyền khi mở công cụ tương ứng và đồng ý. Phần xem thử trên trang này dùng tư liệu từ từ điển.',
        ),
        (
          'Kết quả nhận diện có luôn chính xác?',
          'Kết quả phụ thuộc vào ký hiệu, ánh sáng và góc camera. Hãy kiểm tra lại trước khi sử dụng trong cuộc trò chuyện.',
        ),
      ])
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700)),
          expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
              ? AnimationStyle.noAnimation
              : null,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 32, 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(a, style: const TextStyle(height: 1.6)),
              ),
            ),
          ],
        ),
    ],
  );
}
