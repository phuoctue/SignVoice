import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../../widgets/device_permission_page.dart';
import '../../services/sign_ai/speech_input.dart';

class SpeechCaptureScreen extends StatefulWidget {
  const SpeechCaptureScreen({super.key, this.listening = false, this.input});
  // Legacy route parameter does not fabricate an active recording.
  final bool listening;
  final SpeechInput? input;
  @override
  State<SpeechCaptureScreen> createState() => _SpeechCaptureScreenState();
}

class _SpeechCaptureScreenState extends State<SpeechCaptureScreen>
    with WidgetsBindingObserver {
  late final SpeechInput _input;
  bool _consent = false;
  @override
  void initState() {
    super.initState();
    _input = widget.input ?? DeviceSpeechInput.instance;
    // S15 has already obtained explicit consent and started the same engine.
    _consent = _input.listening;
    _input.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (!mounted) return;
    final state = context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
    if (state != null && state.microphoneAllowed != _input.permissionGranted) {
      state.update(() => state.microphoneAllowed = _input.permissionGranted);
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_input.cancel());
    }
  }

  Future<void> _start() async {
    setState(() => _consent = true);
    await _input.start();
    if (mounted) _changed();
  }

  void _result() {
    if (_input.text.trim().isEmpty) return;
    final state = AppScope.of(context);
    state.update(() => state.transcript = _input.text.trim());
    openScreen(context, 'S18', replace: true);
  }

  @override
  void dispose() {
    _input.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_input.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_consent
      ? DevicePermissionPage(camera: false, onAllow: _start)
      : AppPage(
          title: 'Giọng nói → Văn bản',
          child: Column(
            children: [
              const SizedBox(height: 24),
              PulseOrb(
                icon: Icons.mic_none,
                color: AppColors.teal,
                animate: _input.listening,
                label: _input.listening ? 'Đang lắng nghe' : 'Microphone',
                onTap: _input.busy || _input.listening ? null : _start,
              ),
              Heading(
                _input.listening ? 'Đang lắng nghe…' : 'Sẵn sàng lắng nghe',
                center: true,
              ),
              const SizedBox(height: 12),
              BodyText(
                _input.busy
                    ? 'Đang chờ quyền microphone…'
                    : _input.listening
                    ? 'Hãy nói rõ ràng bằng tiếng Việt.'
                    : 'Bấm microphone và chọn Cho phép khi trình duyệt hoặc thiết bị hỏi.',
                center: true,
              ),
              const SizedBox(height: 20),
              if (_input.error != null) ...[
                Notice(_input.error!, color: AppColors.red),
                const SizedBox(height: 16),
              ],
              if (_input.text.isNotEmpty) ...[
                AppCard(
                  child: Text(
                    _input.text,
                    style: const TextStyle(fontSize: 23, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_input.busy)
                const CircularProgressIndicator()
              else if (_input.listening)
                AppButton(
                  'Dừng ghi nhận',
                  color: AppColors.red,
                  icon: Icons.stop,
                  onPressed: _input.stop,
                )
              else
                AppButton(
                  _input.permissionGranted
                      ? 'Bắt đầu ghi nhận'
                      : 'Cho phép microphone',
                  color: AppColors.teal,
                  icon: Icons.mic,
                  onPressed: _start,
                ),
              if (_input.text.trim().isNotEmpty &&
                  !_input.listening &&
                  !_input.busy) ...[
                const SizedBox(height: 12),
                AppButton(
                  'Xem văn bản',
                  color: AppColors.blue,
                  onPressed: _result,
                ),
              ],
              const SizedBox(height: 20),
              const Notice(
                'Nhận dạng tiếng Việt bằng trình duyệt/thiết bị, có thể cần Internet. Chỉ bật microphone sau khi bạn chọn ghi nhận.',
                color: AppColors.teal,
              ),
            ],
          ),
        );
}

class TranscriptScreen extends StatefulWidget {
  const TranscriptScreen({super.key, this.fullscreen = false});
  final bool fullscreen;
  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  double fontSize = 28;
  @override
  void initState() {
    super.initState();
    if (widget.fullscreen) fontSize = 40;
  }

  void changeSize(double delta) =>
      setState(() => fontSize = (fontSize + delta).clamp(18, 72).toDouble());
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final text = state.transcript;
    if (widget.fullscreen) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: () => backOrHome(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                    const Expanded(
                      child: Text(
                        'Toàn màn hình',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Giảm cỡ chữ',
                      onPressed: () => changeSize(-6),
                      icon: const Icon(Icons.remove, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: 'Tăng cỡ chữ',
                      onPressed: () => changeSize(6),
                      icon: const Icon(Icons.add, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: AppButton(
                  'Quay lại',
                  outlined: true,
                  color: Colors.white,
                  onPressed: () => backOrHome(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AppPage(
      title: 'Kết quả văn bản',
      actions: [
        IconButton(
          tooltip: 'Giảm cỡ chữ',
          onPressed: () => changeSize(-4),
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          tooltip: 'Tăng cỡ chữ',
          onPressed: () => changeSize(4),
          icon: const Icon(Icons.add),
        ),
      ],
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            'Toàn màn hình',
            color: AppColors.teal,
            icon: Icons.fullscreen,
            onPressed: () => openScreen(context, 'S19'),
          ),
          const SizedBox(height: 10),
          AppButton(
            'Ghi nhận lại',
            outlined: true,
            icon: Icons.refresh,
            onPressed: () => openScreen(context, 'S16', replace: true),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SignVoiceBadge(
            'Văn bản ghi nhận',
            color: AppColors.teal,
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(height: 18),
          AppCard(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 180),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AppButton(
            'Chỉnh sửa văn bản',
            secondary: true,
            icon: Icons.edit_outlined,
            onPressed: () async {
              final result = await editText(
                context,
                title: 'Chỉnh sửa văn bản',
                initial: text,
              );
              if (result != null && result.isNotEmpty) {
                state.update(() => state.transcript = result);
              }
            },
          ),
          const SizedBox(height: 10),
          AppButton(
            'Sao chép',
            outlined: true,
            icon: Icons.copy_outlined,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) toast(context, 'Đã sao chép văn bản.');
            },
          ),
          const SizedBox(height: 10),
          AppButton(
            'Lưu lịch sử',
            color: AppColors.green,
            secondary: true,
            icon: Icons.save_outlined,
            onPressed: () {
              state.saveConversation(text, ConversationDirection.speechToText);
              openScreen(context, 'SS03');
            },
          ),
        ],
      ),
    );
  }
}
