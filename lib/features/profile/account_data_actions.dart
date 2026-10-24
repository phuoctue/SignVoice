import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/user/data_export.dart';
import '../../widgets/ui.dart';

class AccountDataActions extends StatefulWidget {
  const AccountDataActions({super.key});
  @override
  State<AccountDataActions> createState() => _AccountDataActionsState();
}

class _AccountDataActionsState extends State<AccountDataActions> {
  bool busy = false;
  String? error, message;
  List<Map<String, dynamic>>? sessions;
  Future<void> _run(
    Future<void> Function(AppState state, int epoch) task,
  ) async {
    final state = AppScope.of(context),
        epoch = AppScope.of(context).accountEpoch;
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await task(state, epoch);
    } catch (failure) {
      if (mounted && state.isCurrent(epoch)) {
        setState(() => error = state.error ?? '$failure');
      }
    } finally {
      if (mounted && state.isCurrent(epoch)) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(
    AppState state,
    int epoch,
    String title,
    String text,
  ) async {
    final result = await confirm(context, title: title, message: text);
    return result && mounted && state.isCurrent(epoch);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (state.service == null) {
      return const Notice('Các thao tác dữ liệu cần kết nối backend.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null) Notice(error!),
        if (message != null) SelectableText(message!),
        IconTile(
          icon: Icons.download_outlined,
          title: 'Xuất dữ liệu cá nhân (JSON)',
          onTap: busy
              ? null
              : () => _run((state, epoch) async {
                  final data = await state.service!.exportData();
                  if (!state.isCurrent(epoch)) return;
                  final result = await exportUserData(
                    const JsonEncoder.withIndent('  ').convert(data),
                  );
                  if (context.mounted && state.isCurrent(epoch)) {
                    setState(() => message = result);
                  }
                }),
        ),
        IconTile(
          icon: Icons.devices_outlined,
          title: 'Phiên đăng nhập',
          onTap: busy
              ? null
              : () => _run((state, epoch) async {
                  final result = await state.service!.sessions();
                  if (context.mounted && state.isCurrent(epoch)) {
                    setState(() => sessions = result);
                  }
                }),
        ),
        if (sessions != null) ...[
          if (sessions!.isEmpty) const Text('Không có phiên hoạt động.'),
          for (final session in sessions!)
            ListTile(
              title: Text(
                session['current'] == true
                    ? 'Thiết bị hiện tại'
                    : 'Thiết bị khác',
              ),
              subtitle: Text(
                '${session['deviceInfo'] ?? 'Không rõ trình duyệt'}\n${session['lastUsedAt']}',
              ),
              trailing: TextButton(
                onPressed: busy
                    ? null
                    : () => _run((state, epoch) async {
                        if (!await _confirm(
                          state,
                          epoch,
                          'Thu hồi phiên?',
                          'Thiết bị này sẽ phải đăng nhập lại.',
                        )) {
                          return;
                        }
                        final current = await state.service!.revokeSession(
                          '${session['_id']}',
                        );
                        if (!context.mounted || !state.isCurrent(epoch)) return;
                        if (current) {
                          await context.read<AuthProvider>().logout();
                          if (context.mounted) openRoot(context, 'S05');
                        } else {
                          final result = await state.service!.sessions();
                          if (context.mounted && state.isCurrent(epoch)) {
                            setState(() => sessions = result);
                          }
                        }
                      }),
                child: const Text('Thu hồi'),
              ),
            ),
        ],
        IconTile(
          icon: Icons.history,
          title: 'Xóa lịch sử hội thoại',
          onTap: busy
              ? null
              : () => _run((state, epoch) async {
                  if (!await _confirm(
                    state,
                    epoch,
                    'Xóa lịch sử?',
                    'Toàn bộ hội thoại của tài khoản này sẽ bị xóa trên máy chủ.',
                  )) {
                    return;
                  }
                  if (!await state.clearHistory()) {
                    throw StateError(state.error ?? 'Không xóa được lịch sử.');
                  }
                  if (context.mounted && state.isCurrent(epoch)) {
                    setState(() => message = 'Đã xóa lịch sử hội thoại.');
                  }
                }),
        ),
        IconTile(
          icon: Icons.delete_sweep_outlined,
          title: 'Xóa dữ liệu cá nhân',
          onTap: busy
              ? null
              : () => _run((state, epoch) async {
                  if (!await _confirm(
                    state,
                    epoch,
                    'Xóa dữ liệu?',
                    'Xóa hội thoại, yêu thích, lịch sử tra cứu và đặt lại cài đặt. Tài khoản được giữ lại.',
                  )) {
                    return;
                  }
                  if (!await state.clearPersistedData()) {
                    throw StateError(state.error ?? 'Không xóa được dữ liệu.');
                  }
                  if (context.mounted && state.isCurrent(epoch)) {
                    setState(() => message = 'Đã xóa dữ liệu trên máy chủ.');
                  }
                }),
        ),
        IconTile(
          icon: Icons.person_remove_outlined,
          title: 'Xóa tài khoản',
          onTap: busy
              ? null
              : () async {
                  final epoch = state.accountEpoch;
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => _DeleteAccountDialog(
                      local: state.accountType == 'LOCAL',
                      submit: (password) async {
                        if (!state.isCurrent(epoch)) {
                          throw StateError('Tài khoản đã thay đổi.');
                        }
                        await state.service!.deleteAccount(password: password);
                        if (!context.mounted || !state.isCurrent(epoch)) return;
                        await context.read<AuthProvider>().logout();
                        if (context.mounted) openRoot(context, 'S05');
                      },
                    ),
                  );
                },
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.local, required this.submit});
  final bool local;
  final Future<void> Function(String?) submit;
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Xóa tài khoản vĩnh viễn?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tài khoản và dữ liệu cá nhân trên máy chủ sẽ bị xóa. Bạn không thể hoàn tác.',
            ),
            if (widget.local)
              TextField(
                controller: password,
                obscureText: true,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu hiện tại',
                ),
              ),
            if (error != null) Text(error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (widget.local && password.text.isEmpty) {
                    setState(() => error = 'Vui lòng nhập mật khẩu.');
                    return;
                  }
                  setState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await widget.submit(widget.local ? password.text : null);
                    if (context.mounted) Navigator.pop(context, true);
                  } catch (failure) {
                    if (context.mounted) {
                      setState(() {
                        error = '$failure';
                        busy = false;
                      });
                    }
                  }
                },
          child: Text(busy ? 'Đang xóa...' : 'Xóa vĩnh viễn'),
        ),
      ],
    ),
  );
}
