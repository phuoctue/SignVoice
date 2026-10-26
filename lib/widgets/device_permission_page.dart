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
      title: camera ? 'Nhận diện ký hiệu' : 'Giọng nói → Hình ảnh',
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
          const SizedBox(height: 12),
          SizedBox(
            height: 156,
            width: 156,
            child: FittedBox(
              child: PulseOrb(
                icon: camera ? Icons.videocam_outlined : Icons.mic_none,
                color: color,
                animate: false,
              ),
            ),
          ),
          Heading('Cho phép sử dụng $device', center: true),
          const SizedBox(height: 16),
          BodyText(
            camera
                ? 'Bật camera để nhận diện ký hiệu. Khung hình được gửi tới dịch vụ AI đã chọn.'
                : 'Bật microphone để nhận lời nói và xem ký hiệu. Có thể cần Internet.',
            center: true,
          ),
          const SizedBox(height: 24),
          Notice(
            error ??
                'Chọn Cho phép khi thiết bị hỏi. Nếu bị chặn, hãy cấp quyền $device trong Cài đặt rồi thử lại.',
            color: error == null ? color : AppColors.red,
            icon: Icons.shield_outlined,
          ),
        ],
      ),
    );
  }
}
