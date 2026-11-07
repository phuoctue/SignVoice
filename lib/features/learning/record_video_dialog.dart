import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

Future<XFile?> recordLearningVideo(BuildContext context) => showDialog<XFile>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const RecordVideoDialog(),
);

class RecordVideoDialog extends StatefulWidget {
  const RecordVideoDialog({super.key});
  @override
  State<RecordVideoDialog> createState() => _RecordVideoDialogState();
}

class _RecordVideoDialogState extends State<RecordVideoDialog> {
  CameraController? _camera;
  bool _loading = true, _busy = false, _recording = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final devices = await availableCameras();
      if (!mounted) return;
      if (devices.isEmpty) throw StateError('No camera');
      final device =
          devices
              .where((d) => d.lensDirection == CameraLensDirection.front)
              .firstOrNull ??
          devices.first;
      final controller = CameraController(
        device,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      _camera = controller;
      await controller.initialize();
    } catch (_) {
      if (mounted) {
        _error = 'Không mở được camera. Hãy cho phép camera và micro, hoặc chọn video có sẵn.';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleRecording() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_recording) {
        final file = await camera.stopVideoRecording();
        await camera.dispose();
        _camera = null;
        if (mounted) Navigator.pop(context, file);
      } else {
        await camera.startVideoRecording();
        if (mounted) setState(() => _recording = true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Chưa quay được video. Hãy thử lại hoặc chọn video có sẵn.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Quay video ký hiệu'),
        leading: IconButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
          tooltip: 'Hủy quay',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : _camera?.value.isInitialized == true
                      ? CameraPreview(_camera!)
                      : const Icon(Icons.videocam_off_outlined, size: 64),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              if (_recording)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Đang quay video…'),
                ),
              FilledButton.icon(
                onPressed:
                    _loading || _busy || _camera?.value.isInitialized != true
                    ? null
                    : _toggleRecording,
                icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
                label: Text(_recording ? 'Dừng và dùng video' : 'Bắt đầu quay'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
