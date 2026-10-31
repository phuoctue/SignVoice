import 'package:flutter/material.dart';

import '../../widgets/ui.dart';
import '../../core/navigation.dart';

class CommunicationHub extends StatelessWidget {
  const CommunicationHub({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Giao tiếp',
    showBack: false,
    contentMaxWidth: 1080,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading('Bạn muốn giao tiếp theo cách nào?', size: 28),
        const SizedBox(height: 12),
        const BodyText(
          'Chọn công cụ phù hợp. Camera và microphone chỉ bật khi bạn cho phép.',
        ),
        const SizedBox(height: 28),
        AdaptiveCardGrid(
          children: [
            for (final item in <(String, String, IconData, String)>[
              (
                'Ký hiệu thành giọng nói',
                'Dùng camera nhận diện ký hiệu và chuyển thành lời nói.',
                Icons.back_hand_outlined,
                '/sign-to-speech',
              ),
              (
                'Giọng nói thành ký hiệu',
                'Nói hoặc nhập văn bản để xem ký hiệu tương ứng.',
                Icons.mic_none,
                '/speech-to-sign',
              ),
            ])
              AppCard(
                onTap: () => openScreen(context, item.$4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.$3,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Heading(item.$1),
                    const SizedBox(height: 12),
                    BodyText(item.$2),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => openScreen(context, item.$4),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      iconAlignment: IconAlignment.end,
                      label: const Text('Bắt đầu'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}
