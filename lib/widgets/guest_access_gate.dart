import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../core/navigation.dart';
import '../core/app_state.dart';
import 'ui.dart';

class GuestAccessGate extends StatefulWidget {
  const GuestAccessGate({
    super.key,
    required this.child,
    this.permanentOnly = false,
  });
  final Widget child;
  final bool permanentOnly;
  @override
  State<GuestAccessGate> createState() => _GuestAccessGateState();
}

class _GuestAccessGateState extends State<GuestAccessGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.permanentOnly) {
        context.read<AuthProvider>().loadGuestTrial();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !widget.permanentOnly) {
      context.read<AuthProvider>().loadGuestTrial();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.user?.isGuest != true) return widget.child;
    if (!widget.permanentOnly &&
        auth.trial?.state == 'active' &&
        !auth.trialExpired &&
        auth.trialError == null) {
      final remaining = auth.trialRemaining;
      final seconds =
          remaining.inSeconds + (remaining.inMilliseconds % 1000 > 0 ? 1 : 0);
      return Column(
        children: [
          SafeArea(
            bottom: false,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Dùng thử · còn ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                      ),
                    ),
                    TextButton(
                      onPressed: () => openScreen(context, 'S06'),
                      child: const Text('Tạo tài khoản'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      );
    }
    final expired = auth.trialExpired;
    final state = context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
    final draft = [
      state?.sentence.join(' ') ?? '',
      state?.transcript ?? '',
    ].where((text) => text.trim().isNotEmpty).join('\n');
    return AppPage(
      title: widget.permanentOnly
          ? 'Cần tài khoản cá nhân'
          : expired
          ? 'Đã hết thời gian dùng thử'
          : 'Dùng thử 10 phút',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_clock_outlined, size: 58),
          const SizedBox(height: 20),
          Text(
            widget.permanentOnly
                ? 'Đăng nhập hoặc tạo tài khoản để lưu hội thoại, yêu thích và đồng bộ dữ liệu.'
                : expired
                ? 'Phiên dùng thử 10 phút đã kết thúc. Đăng nhập hoặc tạo tài khoản để tiếp tục. Bạn vẫn xem được từ điển công khai.'
                : 'Bạn được thử một phiên 10 phút. Thời gian bắt đầu khi bấm nút bên dưới và vẫn tiếp tục khi rời trang hoặc tải lại.',
          ),
          const SizedBox(height: 18),
          if (expired && draft.isNotEmpty) ...[
            const Text('Bản nháp của bạn'),
            SelectableText(draft),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: draft)),
              icon: const Icon(Icons.copy),
              label: const Text('Sao chép bản nháp'),
            ),
          ],
          if (!widget.permanentOnly && !expired)
            AppButton(
              auth.trialLoading
                  ? 'Đang kiểm tra…'
                  : auth.trial == null
                  ? 'Kiểm tra phiên dùng thử'
                  : 'Bắt đầu phiên thử 10 phút',
              onPressed: auth.trialLoading
                  ? null
                  : () => auth.loadGuestTrial(start: auth.trial != null),
            ),
          if (auth.trialError != null) ...[
            Notice(auth.trialError!),
            TextButton(
              onPressed: auth.trialLoading ? null : () => auth.loadGuestTrial(),
              child: const Text('Thử lại'),
            ),
          ],
          AppButton('Đăng nhập', onPressed: () => openScreen(context, 'S05')),
          AppButton(
            'Tạo tài khoản',
            outlined: true,
            onPressed: () => openScreen(context, 'S06'),
          ),
          TextButton(
            onPressed: () => openRoot(context, 'S22'),
            child: const Text('Xem từ điển công khai'),
          ),
        ],
      ),
    );
  }
}
