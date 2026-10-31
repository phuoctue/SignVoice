import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/learning/learning_service.dart';
import '../../services/sign_ai/media_access_error.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';

abstract interface class QuizMirror {
  Future<void> initialize();
  double get aspectRatio;
  Widget preview();
  Future<void> close();
}

QuizMirror createQuizMirror() => _DeviceMirror();

/// Preview only: no audio, recording, hand model, upload or recognition session.
class _DeviceMirror implements QuizMirror {
  CameraController? _controller;
  bool _closed = false;
  @override
  Future<void> initialize() async {
    final devices = await availableCameras();
    if (devices.isEmpty) throw StateError('Không tìm thấy camera.');
    if (_closed) return;
    final device =
        devices
            .where((d) => d.lensDirection == CameraLensDirection.front)
            .firstOrNull ??
        devices.first;
    final controller = CameraController(
      device,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _controller = controller;
    await controller.initialize();
    if (_closed) await close();
  }

  @override
  double get aspectRatio {
    final value = _controller!.value;
    return value.deviceOrientation == DeviceOrientation.portraitUp ||
            value.deviceOrientation == DeviceOrientation.portraitDown
        ? 1 / value.aspectRatio
        : value.aspectRatio;
  }

  @override
  Widget preview() => CameraPreview(_controller!);
  @override
  Future<void> close() async {
    _closed = true;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

class QuizPracticeSheet extends StatefulWidget {
  const QuizPracticeSheet({
    super.key,
    required this.word,
    this.mirrorFactory = createQuizMirror,
  });
  final LearningRecord word;
  final QuizMirror Function() mirrorFactory;
  @override
  State<QuizPracticeSheet> createState() => _QuizPracticeSheetState();
}

class _QuizPracticeSheetState extends State<QuizPracticeSheet>
    with WidgetsBindingObserver {
  QuizMirror? mirror;
  bool busy = false, ready = false;
  int generation = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stop(update: false));
    super.dispose();
  }

  Future<void> start() async {
    if (busy || mirror != null) return;
    final request = ++generation, created = widget.mirrorFactory();
    setState(() {
      busy = true;
      error = null;
      mirror = created;
    });
    try {
      await created.initialize();
      if (!mounted || request != generation) return;
      setState(() {
        ready = true;
        busy = false;
      });
    } catch (e) {
      if (!mounted || request != generation) return;
      await stop();
      if (mounted) {
        setState(
          () => error = e is CameraException
              ? mediaAccessError(e.code).message
              : 'Chưa mở được camera. Bạn vẫn có thể xem mẫu và ôn tiếp.',
        );
      }
    }
  }

  Future<void> stop({bool update = true}) async {
    final request = ++generation, active = mirror;
    mirror = null;
    ready = false;
    if (update && mounted) setState(() => busy = true);
    try {
      await active?.close();
    } catch (_) {
      /* Closing the sheet must always remain possible. */
    }
    if (update && mounted && request == generation) {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .9,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            children: [
              const Expanded(child: Heading('Tự thực hành', size: 21)),
              IconButton(
                tooltip: 'Đóng tự thực hành',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Heading('${widget.word['word']}', size: 20),
                const SizedBox(height: 8),
                const BodyText(
                  'So sánh động tác của bạn với mẫu. Phần này không chấm điểm và không ghi hình.',
                ),
                const SizedBox(height: 16),
                LearningWordContent(
                  widget.word,
                  showMeaning: false,
                  quizControls: true,
                  previewHeight: 160,
                  showFrames: false,
                ),
                const SizedBox(height: 16),
                if (ready && mirror != null) ...[
                  const Heading('Camera của bạn', size: 17),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final ratio = mirror!.aspectRatio;
                      final height = math.min(
                        220.0,
                        constraints.maxWidth / ratio,
                      );
                      return Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            height: height,
                            width: height * ratio,
                            child: mirror!.preview(),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    'Tắt camera',
                    outlined: true,
                    icon: Icons.videocam_off_outlined,
                    onPressed: busy ? null : () => stop(),
                  ),
                ] else
                  AppButton(
                    'Mở camera để soi động tác',
                    icon: Icons.videocam_outlined,
                    busy: busy,
                    onPressed: busy ? null : start,
                  ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Notice(error!),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
