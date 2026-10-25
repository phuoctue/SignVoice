import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/password_input.dart';
import '../../widgets/ui.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    current.dispose();
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      saving = true;
      error = null;
    });
    final success = await auth.changePassword(
      currentPassword: current.text,
      newPassword: password.text,
    );
    if (success && messenger.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Đã đổi mật khẩu. Vui lòng đăng nhập lại bằng mật khẩu mới.',
          ),
        ),
      );
    }
    if (mounted) {
      setState(() {
        saving = false;
        if (!success) {
          error = auth.errorMessage ?? 'Chưa đổi được mật khẩu. Hãy thử lại.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return AppPage(
      title: 'Đổi mật khẩu',
      child: user?.accountType != AccountType.local || user?.isGuest == true
          ? const Notice(
              'Tài khoản Google/Facebook quản lý mật khẩu tại nhà cung cấp đăng nhập. Tài khoản dùng thử cần tạo tài khoản email trước.',
            )
          : Form(
              key: form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BodyText(
                      'Nhập mật khẩu hiện tại và nhập mật khẩu mới hai lần. Sau khi đổi thành công, bạn cần đăng nhập lại trên các thiết bị.',
                    ),
                    const SizedBox(height: 24),
                    PasswordInput(
                      controller: current,
                      label: 'Mật khẩu hiện tại',
                      hint: 'Nhập mật khẩu đang dùng',
                      enabled: !saving,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Vui lòng nhập mật khẩu hiện tại.'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    PasswordInput(
                      controller: password,
                      label: 'Mật khẩu mới',
                      hint: 'Nhập mật khẩu mới',
                      newPassword: true,
                      enabled: !saving,
                      helper: 'Dùng 8–128 ký tự, gồm chữ cái và số; khác mật khẩu hiện tại.',
                      validator: (value) =>
                          validateNewPassword(value) ??
                          (value == current.text
                              ? 'Mật khẩu mới phải khác mật khẩu hiện tại.'
                              : null),
                    ),
                    const SizedBox(height: 20),
                    PasswordInput(
                      controller: repeat,
                      label: 'Nhập lại mật khẩu mới',
                      hint: 'Nhập lại chính xác mật khẩu mới',
                      newPassword: true,
                      enabled: !saving,
                      validator: (value) => value == null || value.isEmpty
                          ? 'Vui lòng nhập lại mật khẩu mới.'
                          : value != password.text
                          ? 'Mật khẩu nhập lại chưa khớp.'
                          : null,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Notice(error!),
                    ],
                    const SizedBox(height: 24),
                    AppButton(
                      'Lưu mật khẩu mới',
                      icon: Icons.lock_reset,
                      busy: saving,
                      onPressed: saving ? null : save,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
