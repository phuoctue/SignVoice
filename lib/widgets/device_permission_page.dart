import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/navigation.dart';
import '../core/theme.dart';
import 'ui.dart';

/// The browser/OS remains responsible for actually granting permission.
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
  Widget mobilePage(BuildContext context) {
    final device = camera ? 'camera' : 'microphone',
        color = camera ? AppColors.blue : AppColors.teal;
    return AppPage(
      title: camera ? 'Ký hiệu thành giọng nói' : 'Giọng nói thành ký hiệu',
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
          AppButton(
            'Cho phép $device',
            icon: camera ? Icons.videocam_outlined : Icons.mic_none,
            color: color,
            busy: busy,
            onPressed: busy ? null : onAllow,
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
                : 'Bật microphone để nhận lời nói và xem ký hiệu.',
            center: true,
          ),
          const SizedBox(height: 24),
          Notice(
            error ??
                'Chọn Cho phép khi thiết bị hỏi. Nếu bị chặn, hãy cấp quyền $device trong Cài đặt rồi thử lại.',
            color: error == null ? color : AppColors.red,
            icon: error == null
                ? Icons.shield_outlined
                : Icons.warning_amber_outlined,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && !isDesktopLayout(context)) return mobilePage(context);
    final device = camera ? 'camera' : 'microphone';
    final color = camera ? AppColors.blue : AppColors.teal;
    return AppPage(
      title: camera ? 'Ký hiệu thành giọng nói' : 'Giọng nói thành ký hiệu',
      contentMaxWidth: 624,
      actions: [
        if (onSettings != null)
          IconButton(
            tooltip: 'Cài đặt nhận diện',
            onPressed: busy ? null : onSettings,
            icon: const Icon(Icons.tune),
          ),
      ],
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  height: 132,
                  width: 132,
                  child: FittedBox(
                    child: PulseOrb(
                      icon: camera ? Icons.videocam_outlined : Icons.mic_none,
                      color: color,
                      animate:
                          kIsWeb && !MediaQuery.disableAnimationsOf(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Heading('Cho phép sử dụng $device', center: true, size: 26),
              const SizedBox(height: 16),
              BodyText(
                camera
                    ? 'Bật camera để nhận diện ký hiệu. Khung hình được gửi tới dịch vụ AI đã chọn.'
                    : 'Bật microphone để nhận lời nói và xem ký hiệu tương ứng.',
                center: true,
              ),
              const SizedBox(height: 24),
              Notice(
                error ?? 'Khi trình duyệt hỏi quyền truy cập, hãy chọn Cho phép. Bạn có thể thay đổi quyền bất cứ lúc nào.',
                color: error == null ? color : AppColors.red,
                icon: error == null
                    ? Icons.shield_outlined
                    : Icons.warning_amber_outlined,
              ),
              if (!camera) ...[
                const SizedBox(height: 12),
                const BodyText(
                  'Nhận giọng nói có thể cần kết nối Internet.',
                  center: true,
                ),
              ],
              const SizedBox(height: 24),
              AppButton(
                'Cho phép $device',
                icon: camera ? Icons.videocam_outlined : Icons.mic_none,
                color: color,
                busy: busy,
                onPressed: busy ? null : onAllow,
                fill: true,
              ),
              if (alternativeAction != null) ...[
                const SizedBox(height: 12),
                alternativeAction!,
              ],
              const SizedBox(height: 12),
              TextButton(
                onPressed: busy ? null : () => backOrHome(context),
                child: const Text('Để sau'),
              ),
              if (error != null)
                TextButton.icon(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Cấp quyền $device'),
                      content: Text(
                        'Nhấn biểu tượng cài đặt ở cạnh địa chỉ trang Web, mở Quyền của trang rồi cho phép $device. Nếu ứng dụng khác đang dùng thiết bị, hãy đóng ứng dụng đó và thử lại.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Đã hiểu'),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.help_outline),
                  label: const Text('Mở hướng dẫn cấp quyền'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
