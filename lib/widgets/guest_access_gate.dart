import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../core/navigation.dart';
import '../core/app_state.dart';
import 'ui.dart';
import 'guest_data_panel.dart';

class GuestAccessGate extends StatefulWidget {
  const GuestAccessGate({
    super.key,
    required this.child,
    this.permanentOnly = false,
    this.returnRoute,
  });
  final Widget child;
  final bool permanentOnly;
  final String? returnRoute;
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
      context.read<AuthProvider>().refreshUser().then((_) {
        if (mounted) context.read<AuthProvider>().loadGuestTrial();
      });
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
        auth.trial?.dataState == 'trial_active' &&
        !auth.trialExpired &&
        !auth.trialLoading &&
        auth.trialError == null) {
      return Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .4,
            ),
            child: const SingleChildScrollView(
              child: GuestDataPanel(compact: true, collapsed: true),
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
      contentMaxWidth: 624,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_clock_outlined, size: 48),
            const SizedBox(height: 16),
            Heading(
              widget.permanentOnly
                  ? 'Lưu dữ liệu với tài khoản của bạn'
                  : expired
                  ? 'Tiếp tục cùng SignVoice'
                  : 'Đang kiểm tra phiên dùng thử',
              center: true,
            ),
            const SizedBox(height: 20),
            GuestDataPanel(returnRoute: widget.returnRoute),
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
            TextButton(
              onPressed: () => openRoot(context, 'S22'),
              child: const Text('Xem từ điển công khai'),
            ),
          ],
        ),
      ),
    );
  }
}
