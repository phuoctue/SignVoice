import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/admin/admin_workspace_service.dart';
import '../../services/api/api_exception.dart';
import '../../widgets/password_input.dart';

class AdminPasswordDialog extends StatefulWidget {
  const AdminPasswordDialog({
    super.key,
    required this.userId,
    required this.name,
    required this.service,
  });
  final String userId, name;
  final AdminWorkspaceService service;
  @override
  State<AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<AdminPasswordDialog> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController(), repeat = TextEditingController();
  late final AuthProvider auth;
  late final int ownerEpoch;
  bool saving = false, closing = false;
  String? error;
  bool get validOwner =>
      auth.isAuthenticated &&
      auth.accountEpoch == ownerEpoch &&
      auth.isAdmin &&
      auth.can('users:write');
  @override
  void initState() {
    super.initState();
    auth = context.read<AuthProvider>();
    ownerEpoch = auth.accountEpoch;
    auth.addListener(checkOwner);
  }

  void checkOwner() {
    if (!mounted || validOwner || closing) return;
    closing = true;
    setState(() {});
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route != null) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  void dispose() {
    auth.removeListener(checkOwner);
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !validOwner || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.service.resetUserPassword(widget.userId, password.text);
      if (mounted && validOwner) Navigator.pop(context, true);
    } catch (e) {
      if (mounted && validOwner) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa đặt lại được mật khẩu. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => !validOwner
      ? const SizedBox.shrink()
      : PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('Đặt lại mật khẩu'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Tài khoản: ${widget.name}'),
                      const SizedBox(height: 12),
                      const Text(
                        'Thao tác này thu hồi các phiên đăng nhập và liên kết đặt lại mật khẩu cũ của tài khoản. Người dùng cần đăng nhập lại bằng mật khẩu mới.',
                      ),
                      const SizedBox(height: 20),
                      PasswordInput(
                        controller: password,
                        label: 'Mật khẩu mới',
                        hint: 'Nhập mật khẩu mới cho tài khoản',
                        helper: 'Dùng 8–128 ký tự, gồm chữ cái và số.',
                        newPassword: true,
                        enabled: !saving,
                        validator: validateNewPassword,
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
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Đang lưu...' : 'Lưu mật khẩu mới'),
              ),
            ],
          ),
        );
}
