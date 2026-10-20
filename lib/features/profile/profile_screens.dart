import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/user/user_service.dart';
import '../../services/api/api_config.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../auth/auth_screens.dart';

const avatarColors = [
  AppColors.blue,
  AppColors.teal,
  AppColors.purple,
  AppColors.green,
];

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final auth = context.watch<AuthProvider>();
    const items = <(String, IconData, String)>[
      ('Chỉnh sửa hồ sơ', Icons.edit_outlined, 'S26'),
      ('Cài đặt giọng nói', Icons.headphones_outlined, 'S27'),
      ('Giao diện & Trợ năng', Icons.light_mode_outlined, 'S28'),
      ('Đồng bộ dữ liệu', Icons.sync, 'S29'),
      ('Quyền riêng tư', Icons.shield_outlined, 'S30'),
      ('Thông tin ứng dụng', Icons.info_outline, 'S31'),
    ];
    return AppPage(
      title: 'Cá nhân',
      showBack: false,
      tabIndex: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.guest) ...[
            const Notice(
              'Bạn đang dùng thử. Đăng nhập để xem luồng tài khoản và đồng bộ demo.',
            ),
            const SizedBox(height: 12),
            AppButton('Đăng nhập', onPressed: () => openRoot(context, 'S05')),
          ] else
            Column(
              children: [
                const SizedBox(height: 12),
                CircleAvatar(
                  radius: 42,
                  backgroundColor: avatarColors[state.avatarColor],
                  child: Text(
                    state.name.isEmpty ? 'S' : state.name[0],
                    style: const TextStyle(
                      fontSize: 30,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Heading(state.name, center: true),
                const SizedBox(height: 5),
                BodyText(state.email, center: true),
              ],
            ),
          const SizedBox(height: 26),
          if (auth.isStaff && !auth.isAdmin) ...[
            IconTile(
              icon: Icons.fact_check_outlined,
              title: 'Quản lý nội dung',
              onTap: () => openScreen(context, 'staff'),
            ),
            const SizedBox(height: 10),
          ],
          for (final item in items) ...[
            IconTile(
              icon: item.$2,
              title: item.$1,
              onTap: () => openScreen(context, item.$3),
            ),
            const SizedBox(height: 10),
          ],
          IconTile(
            icon: Icons.logout,
            title: state.guest ? 'Kết thúc dùng thử' : 'Đăng xuất',
            color: AppColors.red,
            onTap: () async {
              if (await confirm(
                context,
                title: 'Đăng xuất?',
                message: 'Bạn sẽ quay về màn hình đăng nhập.',
              )) {
                await auth.logout();
                if (context.mounted) openRoot(context, 'S05');
              }
            },
          ),
        ],
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), email = TextEditingController();
  bool initialized = false, saved = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      final state = AppScope.of(context);
      name.text = state.name;
      email.text = state.email;
      initialized = true;
    }
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AppPage(
      title: 'Chỉnh sửa hồ sơ',
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: avatarColors[state.avatarColor],
                child: Text(
                  state.name.isEmpty ? 'S' : state.name[0],
                  style: const TextStyle(fontSize: 32, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const BodyText('Chọn màu ảnh đại diện', center: true),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                avatarColors.length,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: IconButton(
                    tooltip: 'Màu đại diện ${i + 1}',
                    style: IconButton.styleFrom(
                      backgroundColor: avatarColors[i],
                    ),
                    onPressed: () => state.update(() => state.avatarColor = i),
                    icon: Icon(
                      state.avatarColor == i ? Icons.check : Icons.circle,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Họ và tên'),
              onChanged: (_) => setState(() => saved = false),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Vui lòng nhập họ và tên.'
                  : null,
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: validateEmail,
              onChanged: (_) => setState(() => saved = false),
            ),
            const SizedBox(height: 22),
            if (saved) ...[
              const Notice(
                'Đã lưu thay đổi trong phiên demo.',
                color: AppColors.green,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(height: 16),
            ],
            AppButton(
              'Lưu thay đổi',
              onPressed: () {
                if (form.currentState!.validate()) {
                  state.update(() {
                    state.name = name.text.trim();
                    state.email = email.text.trim();
                  });
                  setState(() => saved = true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceSettingsScreen extends StatelessWidget {
  const VoiceSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    Widget slider(
      String title,
      double value,
      String low,
      String high,
      ValueChanged<double> change,
    ) => Column(
      children: [
        Row(
          children: [
            Expanded(child: Heading(title, size: 16)),
            SignVoiceBadge(value.toStringAsFixed(1)),
          ],
        ),
        Slider(
          value: value,
          min: .5,
          max: 2,
          divisions: 15,
          label: value.toStringAsFixed(1),
          onChanged: change,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [BodyText(low), BodyText(high)],
        ),
      ],
    );
    return AppPage(
      title: 'Cài đặt giọng nói',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              children: [
                slider(
                  'Tốc độ đọc',
                  state.speechSpeed,
                  'Chậm',
                  'Nhanh',
                  (v) => state.update(() => state.speechSpeed = v),
                ),
                const SizedBox(height: 22),
                slider(
                  'Cao độ',
                  state.speechPitch,
                  'Thấp',
                  'Cao',
                  (v) => state.update(() => state.speechPitch = v),
                ),
                const SizedBox(height: 18),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tự động phát'),
                  subtitle: const Text('Mở trình phát khi xác nhận câu'),
                  value: state.autoSpeak,
                  onChanged: (v) => state.update(() => state.autoSpeak = v),
                ),
                const Divider(),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Ngôn ngữ'),
                  subtitle: Text('Tiếng Việt (VI)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppButton(
            'Nghe thử giọng đọc',
            secondary: true,
            icon: Icons.volume_up_outlined,
            onPressed: () {
              state.update(() {
                state.sentence.clear();
                state.sentence.add('Xin chào, chào mừng bạn đến với SignVoice');
              });
              openScreen(context, 'S14');
            },
          ),
          const SizedBox(height: 18),
          const Notice(
            'Tốc độ và cao độ đã lưu trong trạng thái FE. '
            'Phát âm thanh thực tế cần tích hợp TTS.',
          ),
        ],
      ),
    );
  }
}

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AppPage(
      title: 'Giao diện & Trợ năng',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Heading('Giao diện', size: 17),
                const SizedBox(height: 18),
                Row(
                  children: List.generate(3, (i) {
                    const modes = [
                      ThemeMode.light,
                      ThemeMode.dark,
                      ThemeMode.system,
                    ];
                    const labels = ['Sáng', 'Tối', 'Hệ thống'];
                    const icons = [
                      Icons.light_mode_outlined,
                      Icons.dark_mode_outlined,
                      Icons.phone_android,
                    ];
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                        child: InkWell(
                          onTap: () =>
                              state.update(() => state.themeMode = modes[i]),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 2,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: state.themeMode == modes[i]
                                  ? AppColors.blue.withAlpha(15)
                                  : null,
                              border: Border.all(
                                color: state.themeMode == modes[i]
                                    ? AppColors.blue
                                    : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                width: state.themeMode == modes[i] ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(icons[i], color: AppColors.blue),
                                const SizedBox(height: 10),
                                Text(
                                  labels[i],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppCard(
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Heading('Cỡ chữ', size: 17),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    IconButton.outlined(
                      tooltip: 'Giảm cỡ chữ',
                      onPressed: state.fontScale <= .9
                          ? null
                          : () => state.update(
                              () => state.fontScale = (state.fontScale - .1)
                                  .clamp(.9, 1.4)
                                  .toDouble(),
                            ),
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Text(
                        'Aa • ${(state.fontScale * 100).round()}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Tăng cỡ chữ',
                      onPressed: state.fontScale >= 1.4
                          ? null
                          : () => state.update(
                              () => state.fontScale = (state.fontScale + .1)
                                  .clamp(.9, 1.4)
                                  .toDouble(),
                            ),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const BodyText(
                  'Cỡ chữ được áp dụng cho toàn ứng dụng.',
                  center: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SwitchListTile(
              title: const Text('Tương phản cao'),
              subtitle: const Text('Tăng độ rõ của chữ và nút'),
              value: state.highContrast,
              onChanged: (v) => state.update(() => state.highContrast = v),
            ),
          ),
        ],
      ),
    );
  }
}

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final status = state.syncing
        ? 'Đang đồng bộ demo...'
        : !state.online
        ? 'Chờ kết nối'
        : state.lastSync == null
        ? 'Sẵn sàng đồng bộ demo'
        : 'Đã đồng bộ demo';
    return AppPage(
      title: 'Đồng bộ dữ liệu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconTile(
            icon: state.syncing
                ? Icons.sync
                : state.online
                ? Icons.check_circle_outline
                : Icons.wifi_off,
            title: status,
            subtitle: state.lastSync == null
                ? 'Chưa có phiên đồng bộ'
                : 'Lần cuối: ${state.lastSync!.hour.toString().padLeft(2, '0')}:${state.lastSync!.minute.toString().padLeft(2, '0')}',
            color: state.online ? AppColors.green : AppColors.red,
            trailing: state.syncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          const SizedBox(height: 18),
          AppCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kết nối demo'),
                  subtitle: Text(state.online ? 'Đang kết nối' : 'Mất kết nối'),
                  value: state.online,
                  onChanged: state.syncing
                      ? null
                      : (v) => state.update(() => state.online = v),
                ),
                const Divider(),
                _CountRow('Lịch sử hội thoại', '${state.history.length} mục'),
                const SizedBox(height: 12),
                _CountRow(
                  'Ký hiệu yêu thích',
                  '${state.favorites.length} ký hiệu',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (state.guest) ...[
            const Notice('Vui lòng đăng nhập để xem luồng đồng bộ demo.'),
            const SizedBox(height: 14),
          ],
          AppButton(
            'Đồng bộ ngay',
            icon: Icons.sync,
            busy: state.syncing,
            onPressed: !state.online || state.guest
                ? null
                : () => state.simulateSync(),
          ),
          const SizedBox(height: 18),
          const Notice(
            'Đồng bộ hiện là mô phỏng. Dữ liệu chỉ giữ trong phiên chạy ứng dụng, '
            'chưa được gửi lên máy chủ.',
          ),
        ],
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: BodyText(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AppPage(
      title: 'Quyền riêng tư',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconTile(
            icon: Icons.policy_outlined,
            title: 'Chính sách quyền riêng tư',
            onTap: () => launchUrl(
              Uri.base.resolve(ApiConfig.baseUrl).resolve('/privacy'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 12),
          IconTile(
            icon: Icons.help_outline,
            title: 'Hướng dẫn xóa dữ liệu',
            onTap: () => launchUrl(
              Uri.base.resolve(ApiConfig.baseUrl).resolve('/data-deletion'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 18),
          const Notice(
            'Camera và microphone chỉ được yêu cầu khi bạn dùng chức năng tương ứng. '
            'Camera được xử lý bởi dịch vụ AI; nhận dạng giọng nói có thể dùng dịch vụ của trình duyệt.',
            icon: Icons.shield_outlined,
          ),
          const SizedBox(height: 18),
          IconTile(
            icon: Icons.camera_alt_outlined,
            title: 'Quyền camera',
            trailing: SignVoiceBadge(
              state.cameraAllowed ? 'Đã cho phép' : 'Chưa cấp',
              color: state.cameraAllowed ? AppColors.green : AppColors.muted,
            ),
            onTap: () => openScreen(context, 'S09'),
          ),
          const SizedBox(height: 10),
          IconTile(
            icon: Icons.mic_none,
            title: 'Quyền microphone demo',
            trailing: SignVoiceBadge(
              state.microphoneAllowed ? 'Đã cho phép' : 'Chưa cấp',
              color: state.microphoneAllowed
                  ? AppColors.green
                  : AppColors.muted,
            ),
            onTap: () => openScreen(context, 'S15'),
          ),
          const SizedBox(height: 24),
          IconTile(
            icon: Icons.history,
            title: 'Xóa lịch sử hội thoại',
            onTap: () async {
              if (await confirm(
                context,
                title: 'Xóa lịch sử?',
                message: 'Tất cả hội thoại demo trong phiên này sẽ bị xóa.',
              )) {
                state.update(() {
                  state.history.clear();
                  state.selectedHistoryId = null;
                });
                if (context.mounted) toast(context, 'Đã xóa lịch sử demo.');
              }
            },
          ),
          const SizedBox(height: 10),
          IconTile(
            icon: Icons.delete_sweep_outlined,
            title: 'Xóa dữ liệu demo',
            onTap: () async {
              if (await confirm(
                context,
                title: 'Xóa dữ liệu demo?',
                message:
                    'Lịch sử, câu hiện tại và ký hiệu yêu thích sẽ bị xóa.',
              )) {
                state.clearLocalData();
                if (context.mounted) {
                  toast(context, 'Đã xóa dữ liệu demo trong phiên.');
                }
              }
            },
          ),
          const SizedBox(height: 10),
          IconTile(
            icon: Icons.person_remove_outlined,
            title: 'Xóa tài khoản',
            color: AppColors.red,
            onTap: () async {
              if (await confirm(
                context,
                title: 'Xóa tài khoản vĩnh viễn?',
                message: 'Tài khoản, hồ sơ, lịch sử, mục yêu thích và cài đặt trên server sẽ bị xóa. Bạn không thể hoàn tác thao tác này.',
              )) {
                try {
                  await UserService.instance.deleteAccount();
                } catch (_) {
                  if (context.mounted) toast(context, 'Chưa xóa được tài khoản. Vui lòng thử lại.');
                  return;
                }
                state.clearLocalData();
                if (!context.mounted) return;
                await context.read<AuthProvider>().logout();
                if (context.mounted) openRoot(context, 'S05');
              }
            },
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Thông tin ứng dụng',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: Logo(size: 72)),
        const SizedBox(height: 18),
        const Heading('SignVoice', size: 28, center: true),
        const SizedBox(height: 6),
        const BodyText('Phiên bản 1.0.0 • Flutter FE', center: true),
        const SizedBox(height: 26),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Heading('Về ứng dụng', size: 17),
              SizedBox(height: 12),
              BodyText(
                'SignVoice hỗ trợ giao tiếp hai chiều giữa người sử dụng ngôn ngữ ký hiệu và người nghe thông thường, '
                'góp phần xóa bỏ rào cản giao tiếp.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Notice(
          'Mục tiêu phiên bản 1.0: 20–50 ký hiệu giao tiếp cơ bản, '
          'ưu tiên một tay. FE hiện có 10 mục từ mẫu và các luồng nhận diện mô phỏng.',
          color: Color(0xFFD97706),
          icon: Icons.warning_amber_outlined,
        ),
        const SizedBox(height: 18),
        IconTile(
          icon: Icons.shield_outlined,
          title: 'Chính sách quyền riêng tư',
          onTap: () => openScreen(context, 'S30'),
        ),
        const SizedBox(height: 10),
        IconTile(
          icon: Icons.description_outlined,
          title: 'Điều khoản demo',
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Điều khoản demo'),
              content: const Text(
                'Đây là nguyên mẫu giao diện phục vụ môn lập trình di động. '
                'Tài khoản và kết quả nhận diện hiện dùng dữ liệu mô phỏng.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Đóng'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        IconTile(
          icon: Icons.bug_report_outlined,
          title: 'Danh mục 37 màn hình',
          onTap: () => openScreen(context, 'catalog'),
        ),
      ],
    ),
  );
}
