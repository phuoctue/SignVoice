import 'package:flutter/material.dart';

/// Picking a mode never discards an existing draft; the server resumes it.
Future<String?> chooseQuizMode(
  BuildContext context,
) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ôn tập theo cách của bạn',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Nếu có lượt chưa hoàn tất, bạn sẽ tiếp tục lượt đó. Kết quả được lưu theo tài khoản.',
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.extension_outlined),
          title: const Text('Ghép cặp ký hiệu'),
          subtitle: const Text(
            'Kéo thả hoặc chạm để ghép nghĩa với mẫu ký hiệu. Có thể thử lại và dùng gợi ý.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pop(context, 'VIDEO_MATCH'),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.psychology_outlined),
          title: const Text('Tự nhớ nghĩa'),
          subtitle: const Text(
            'Xem mẫu, tự nhập nghĩa rồi đối chiếu để củng cố khả năng ghi nhớ.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pop(context, 'VIDEO_RECALL'),
        ),
      ],
    ),
  ),
);
