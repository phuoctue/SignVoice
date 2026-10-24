import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import 'account_data_actions.dart';
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
              'Bạn có một phiên dùng thử 10 phút, tính từ lúc bắt đầu. Tạo tài khoản để tiếp tục phiên dịch, lưu hội thoại và đồng bộ.',
            ),
            const SizedBox(height: 12),
            AppButton(
              'Tạo tài khoản và giữ dữ liệu',
              onPressed: () => openScreen(context, 'S06'),
            ),
          ] else
            Column(
              children: [
                const SizedBox(height: 12),
                CircleAvatar(
                  radius: 42,
                  backgroundColor: avatarColors[state.avatarColor],
                  foregroundImage: state.avatarUrl.isEmpty
                      ? null
                      : NetworkImage(state.avatarUrl),
                  onForegroundImageError: state.avatarUrl.isEmpty
                      ? null
                      : (_, _) {},
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
              final epoch = auth.accountEpoch;
              if (await confirm(
                context,
                title: 'Đăng xuất?',
                message: 'Bạn sẽ quay về màn hình đăng nhập.',
              )) {
                if (!context.mounted || auth.accountEpoch != epoch) return;
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
  final name = TextEditingController(),
      email = TextEditingController(),
      avatar = TextEditingController(),
      password = TextEditingController();
  bool initialized = false, loading = true, saving = false;
  String? error;
  int color = 0;
  late int epoch;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      epoch = AppScope.of(context).accountEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = state.service == null
          ? {
              'displayName': state.name,
              'email': state.email,
              'avatarUrl': state.avatarUrl,
            }
          : await state.service!.profile();
      if (!mounted || (state.persisted && !state.isCurrent(epoch))) return;
      name.text = '${data['displayName']}';
      email.text = '${data['email'] ?? ''}';
      avatar.text = '${data['avatarUrl'] ?? ''}';
      color = state.avatarColor;
      setState(() => loading = false);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = '$failure';
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [name, email, avatar, password]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final state = AppScope.of(context);
    if (!form.currentState!.validate() ||
        (state.persisted && !state.isCurrent(epoch))) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final auth = context.read<AuthProvider>();
    final success = await state.saveProfile({
      'displayName': name.text.trim(),
      'avatarUrl': avatar.text.trim(),
      if (state.accountType == 'LOCAL' && email.text.trim() != state.email)
        'email': email.text.trim(),
      if (password.text.isNotEmpty) 'currentPassword': password.text,
    });
    if (!mounted || (state.persisted && !state.isCurrent(epoch))) return;
    if (!success) {
      setState(() {
        saving = false;
        error = state.error ?? 'Không lưu được hồ sơ.';
      });
      return;
    }
    final preferencesSaved = await state.saveSettings({'avatarColor': color});
    if (!mounted || (state.persisted && !state.isCurrent(epoch))) return;
    await auth.refreshUser();
    if (!mounted || (state.persisted && !state.isCurrent(epoch))) return;
    setState(() {
      saving = false;
      error = preferencesSaved ? null : state.error;
    });
    if (preferencesSaved) {
      password.clear();
      toast(context, 'Đã lưu hồ sơ trên máy chủ.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PopScope(
      canPop: !saving,
      child: AppPage(
        title: 'Chỉnh sửa hồ sơ',
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null) ...[
                Notice(error!),
                if (name.text.isEmpty)
                  TextButton(onPressed: _load, child: const Text('Thử lại')),
              ],
              if (!loading && name.text.isNotEmpty) ...[
                CircleAvatar(
                  radius: 44,
                  backgroundColor: avatarColors[color],
                  foregroundImage: state.avatarUrl.isEmpty
                      ? null
                      : NetworkImage(state.avatarUrl),
                  onForegroundImageError: state.avatarUrl.isEmpty
                      ? null
                      : (_, _) {},
                  child: Text(
                    name.text.isEmpty ? 'S' : name.text[0],
                    style: const TextStyle(fontSize: 32, color: Colors.white),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    for (var i = 0; i < avatarColors.length; i++)
                      IconButton(
                        onPressed: saving
                            ? null
                            : () => setState(() => color = i),
                        tooltip: 'Màu đại diện ${i + 1}',
                        icon: Icon(
                          color == i ? Icons.check_circle : Icons.circle,
                          color: avatarColors[i],
                        ),
                      ),
                  ],
                ),
                TextFormField(
                  controller: name,
                  enabled: !saving,
                  decoration: const InputDecoration(labelText: 'Họ và tên'),
                  validator: (value) =>
                      (value?.trim().length ?? 0) < 2 ||
                          (value?.trim().length ?? 0) > 50
                      ? 'Tên cần từ 2 đến 50 ký tự.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: email,
                  enabled: !saving && state.accountType == 'LOCAL',
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: state.accountType == 'LOCAL'
                      ? validateEmail
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
                if (state.accountType == 'LOCAL' &&
                    email.text.trim() != state.email)
                  TextFormField(
                    controller: password,
                    enabled: !saving,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu hiện tại để đổi email',
                    ),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Vui lòng nhập mật khẩu hiện tại.'
                        : null,
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: avatar,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'URL ảnh đại diện (tùy chọn)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final uri = Uri.tryParse(value.trim());
                    return uri == null ||
                            !['http', 'https'].contains(uri.scheme) ||
                            uri.host.isEmpty
                        ? 'Dùng URL HTTP hoặc HTTPS hợp lệ.'
                        : null;
                  },
                ),
                const SizedBox(height: 24),
                AppButton(
                  'Lưu thay đổi',
                  busy: saving,
                  onPressed: saving ? null : _save,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> savePreference(
  BuildContext context,
  AppState state,
  Map<String, dynamic> changes,
) async {
  final epoch = state.accountEpoch;
  state.update(() => state.saving = true);
  final success = await state.saveSettings(changes);
  if (state.persisted && !state.isCurrent(epoch)) return false;
  state.update(() => state.saving = false);
  if (!success && context.mounted) {
    toast(context, state.error ?? 'Không lưu được cài đặt.');
  }
  return success;
}

class _PreferenceSlider extends StatefulWidget {
  const _PreferenceSlider({
    required this.label,
    required this.value,
    required this.save,
    this.enabled = true,
  });
  final String label;
  final double value;
  final bool enabled;
  final Future<bool> Function(double) save;
  @override
  State<_PreferenceSlider> createState() => _PreferenceSliderState();
}

class _PreferenceSliderState extends State<_PreferenceSlider> {
  late double draft = widget.value;
  bool dragging = false;
  @override
  void didUpdateWidget(covariant _PreferenceSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!dragging) draft = widget.value;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('${widget.label}: ${draft.toStringAsFixed(1)}'),
      Slider(
        value: draft.clamp(.5, 2),
        min: .5,
        max: 2,
        divisions: 15,
        onChanged: widget.enabled
            ? (value) => setState(() {
                dragging = true;
                draft = value;
              })
            : null,
        onChangeEnd: widget.enabled
            ? (value) async {
                await widget.save(value);
                if (mounted) {
                  setState(() {
                    dragging = false;
                    draft = widget.value;
                  });
                }
              }
            : null,
      ),
    ],
  );
}

class VoiceSettingsScreen extends StatelessWidget {
  const VoiceSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AppPage(
      title: 'Cài đặt giọng nói',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.saving) const LinearProgressIndicator(),
          _PreferenceSlider(
            label: 'Tốc độ đọc',
            value: state.speechSpeed,
            enabled: !state.saving,
            save: (value) =>
                savePreference(context, state, {'speechSpeed': value}),
          ),
          _PreferenceSlider(
            label: 'Cao độ',
            value: state.speechPitch,
            enabled: !state.saving,
            save: (value) =>
                savePreference(context, state, {'speechPitch': value}),
          ),
          SwitchListTile(
            title: const Text('Tự động phát'),
            subtitle: const Text('Mở trình phát khi xác nhận câu'),
            value: state.autoSpeak,
            onChanged: state.saving
                ? null
                : (value) =>
                      savePreference(context, state, {'autoSpeak': value}),
          ),
          const SizedBox(height: 18),
          AppButton(
            'Nghe thử giọng đọc',
            onPressed: () {
              state.update(() {
                state.sentence
                  ..clear()
                  ..add('Xin chào, chào mừng bạn đến với SignVoice');
              });
              openScreen(context, 'S14');
            },
          ),
          const SizedBox(height: 18),
          const Notice(
            'Cài đặt được lưu theo tài khoản. Giọng tiếng Việt phụ thuộc trình duyệt hoặc thiết bị.',
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
          if (state.saving) const LinearProgressIndicator(),
          const Heading('Giao diện', size: 17),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              for (final mode in ThemeMode.values)
                ChoiceChip(
                  label: Text(switch (mode) {
                    ThemeMode.system => 'Hệ thống',
                    ThemeMode.light => 'Sáng',
                    ThemeMode.dark => 'Tối',
                  }),
                  selected: state.themeMode == mode,
                  onSelected: state.saving
                      ? null
                      : (_) => savePreference(context, state, {
                          'theme': mode.name.toUpperCase(),
                        }),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text('Cỡ chữ: ${(state.fontScale * 100).round()}%'),
          Wrap(
            spacing: 12,
            children: [
              for (final size in [14, 16, 18, 20, 22, 24])
                ChoiceChip(
                  label: Text('$size'),
                  selected: (state.fontScale * 16).round() == size,
                  onSelected: state.saving
                      ? null
                      : (_) =>
                            savePreference(context, state, {'fontSize': size}),
                ),
            ],
          ),
          SwitchListTile(
            title: const Text('Tương phản cao'),
            value: state.highContrast,
            onChanged: state.saving
                ? null
                : (value) =>
                      savePreference(context, state, {'highContrast': value}),
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
    return AppPage(
      title: 'Đồng bộ dữ liệu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IconTile(
            icon: Icons.sync,
            title: state.syncing
                ? 'Đang tải dữ liệu từ máy chủ...'
                : 'Dữ liệu tài khoản',
            subtitle: state.lastSync == null
                ? 'Chưa tải dữ liệu thành công.'
                : 'Tải gần nhất: ${state.lastSync!.toLocal()}',
          ),
          if (state.syncing) const LinearProgressIndicator(),
          if (state.error != null) Notice(state.error!),
          const SizedBox(height: 16),
          Text('Hội thoại đã tải: ${state.history.length}'),
          Text('Ký hiệu yêu thích: ${state.favorites.length}'),
          const SizedBox(height: 20),
          AppButton(
            'Đồng bộ ngay',
            busy: state.syncing,
            onPressed: state.syncing
                ? null
                : () async {
                    final success = await state.synchronize();
                    if (context.mounted) {
                      toast(
                        context,
                        success
                            ? 'Đã tải lại dữ liệu đã lưu trên máy chủ.'
                            : state.error ?? 'Không đồng bộ được.',
                      );
                    }
                  },
          ),
          const SizedBox(height: 16),
          const Notice(
            'Hồ sơ, cài đặt, yêu thích và lịch sử hội thoại được tải lại từ tài khoản hiện tại. Hội thoại được phân trang.',
          ),
        ],
      ),
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
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
          'Camera và microphone chỉ được yêu cầu khi bạn dùng chức năng tương ứng. Camera được xử lý bởi dịch vụ AI; nhận dạng giọng nói có thể dùng dịch vụ của trình duyệt.',
        ),
        IconTile(
          icon: Icons.camera_alt_outlined,
          title: 'Camera',
          onTap: () => openScreen(context, 'S09'),
        ),
        IconTile(
          icon: Icons.mic_none,
          title: 'Microphone',
          onTap: () => openScreen(context, 'S15'),
        ),
        const SizedBox(height: 20),
        const AccountDataActions(),
      ],
    ),
  );
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
          'SignVoice đang sử dụng bộ model 181 từ. '
          'Chất lượng nhận diện và độ phủ video còn phụ thuộc dữ liệu và thiết bị.',
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
          title: 'Điều khoản sử dụng',
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Điều khoản sử dụng'),
              content: const Text(
                'SignVoice hỗ trợ giao tiếp và tham khảo ngôn ngữ ký hiệu. '
                'Hãy kiểm tra lại kết quả nhận diện trước khi sử dụng trong giao tiếp quan trọng.',
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
          title: 'Danh mục màn hình',
          onTap: () => openScreen(context, 'catalog'),
        ),
      ],
    ),
  );
}
