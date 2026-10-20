import 'package:flutter/material.dart';

import '../core/navigation.dart';
import '../core/theme.dart';
import 'ui.dart';

/// Explains access before invoking any camera or speech platform API.
/// The browser/OS remains responsible for granting the actual permission.
class DevicePermissionPage extends StatelessWidget {
  const DevicePermissionPage({
    super.key,
    required this.camera,
    required this.onAllow,
    this.onSettings,
    this.busy = false,
    this.error,
    this.alternativeAction,
  });

  final bool camera, busy;
  final VoidCallback onAllow;
  final VoidCallback? onSettings;
  final String? error;
  final Widget? alternativeAction;

  @override
  Widget build(BuildContext context) {
    final device = camera ? 'camera' : 'microphone';
    final color = camera ? AppColors.blue : AppColors.teal;
    return AppPage(
      title: camera ? 'Nhận diện ký hiệu' : 'Giọng nói → Văn bản',
      actions: [
        if (onSettings != null)
          IconButton(
            tooltip: 'Cài đặt nhận diện',
            onPressed: busy ? null : onSettings,
            icon: const Icon(Icons.tune),
          ),
      ],
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const CircularProgressIndicator()
          else
            AppButton(
              'Cho phép $device',
              color: color,
              icon: camera ? Icons.videocam_outlined : Icons.mic,
              onPressed: onAllow,
            ),
          const SizedBox(height: 12),
          ?alternativeAction,
          TextButton(
            onPressed: busy ? null : () => backOrHome(context),
            child: const Text('Để sau'),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          PulseOrb(
            icon: camera ? Icons.videocam_outlined : Icons.mic_none,
            color: color,
            animate: false,
          ),
          Heading('Cho phép sử dụng $device', center: true),
          const SizedBox(height: 16),
          BodyText(
            camera
                ? 'Camera chỉ bật sau khi bạn đồng ý. Khi kết nối AI, khung hình được gửi tới service AI đã cấu hình để nhận diện ký hiệu. Tính năng này không bật microphone.'
                : 'Microphone chỉ bật sau khi bạn đồng ý để chuyển lời nói thành văn bản. Dịch vụ nhận dạng của trình duyệt hoặc thiết bị có thể cần Internet. Đọc kết quả bằng loa không cần quyền microphone.',
            center: true,
          ),
          const SizedBox(height: 24),
          Notice(
            error ??
                'Bấm Cho phép $device để tiếp tục. Trình duyệt hoặc thiết bị sẽ hỏi quyền nếu chưa cấp. Nếu đã cho phép trước đó, thông báo hệ thống có thể không hiện lại. Nếu từng chọn Chặn, hãy đổi quyền $device trong Cài đặt trang web rồi thử lại.',
            color: error == null ? color : AppColors.red,
            icon: Icons.shield_outlined,
          ),
        ],
      ),
    );
  }
}
