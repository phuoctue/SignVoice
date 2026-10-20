import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_types.dart';
import 'media_access_error.dart';
import 'local_hand_tracker_native.dart';

SignCamera createSignCamera({required bool front}) => NativeSignCamera(front);

class NativeSignCamera implements SignCamera, LocalTrackingCamera {
  NativeSignCamera(this._requestedFront);
  final bool _requestedFront;
  CameraController? _controller;
  NativeHandTracker? _tracker;
  StreamSubscription<CapturedFrame>? _frames;
  final _local = StreamController<LocalHandObservation>.broadcast();
  StreamSubscription<LocalHandObservation>? _observations;
  @override
  Stream<LocalHandObservation> get localTracking => _local.stream;
  bool _closed = false;
  final _captureClock = Stopwatch();
  int _lastCaptureMs = -1000;
  @override
  bool get front =>
      _controller?.description.lensDirection == CameraLensDirection.front;
  @override
  double get aspectRatio {
    final c = _controller;
    if (c == null) {
      return 4 / 3;
    }
    final portrait =
        c.value.deviceOrientation == DeviceOrientation.portraitUp ||
        c.value.deviceOrientation == DeviceOrientation.portraitDown;
    return portrait ? 1 / c.value.aspectRatio : c.value.aspectRatio;
  }

  @override
  Future<void> initialize() async {
    try {
      final devices = await availableCameras();
      if (devices.isEmpty) {
        throw StateError('Không tìm thấy camera trên thiết bị.');
      }
      final desired = _requestedFront
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final device =
          devices.where((d) => d.lensDirection == desired).firstOrNull ??
          devices.first;
      final c = CameraController(
        device,
        ResolutionPreset.medium,
        enableAudio: false,
        fps: 30,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      _controller = c;
      await c.initialize();
      if (_closed) {
        await c.dispose();
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final tracker = NativeHandTracker();
        _tracker = tracker;
        _observations = tracker.observations.listen((observation) {
          final stamp = observation.timestampMs;
          _local.add(
            LocalHandObservation(
              observation.landmarks,
              observation.fps,
              observation.processingMs,
              captureSource: observation.captureSource,
              timestampMs: stamp,
              handObservation: observation.handObservation,
              captureAgeMs: stamp == null
                  ? null
                  : (_captureClock.elapsedMilliseconds - stamp)
                        .clamp(0, double.infinity)
                        .toDouble(),
            ),
          );
        });
        await tracker.initialize();
        if (_closed) {
          await tracker.close();
          return;
        }
      }
      try {
        await c.setFlashMode(FlashMode.off);
      } on CameraException {
        /* Not all cameras have flash. */
      }
    } on CameraException catch (error) {
      throw mediaAccessError(error.code);
    }
  }

  int _rotation(CameraController c) {
    const offsets = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final sensor = c.description.sensorOrientation;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return sensor;
    }
    final device = offsets[c.value.deviceOrientation] ?? 0;
    return (sensor + (front ? device : -device) + 360) % 360;
  }

  @override
  Widget preview() => _controller == null
      ? const SizedBox.shrink()
      : CameraPreview(_controller!);

  @override
  Future<void> start(
    void Function(CapturedFrame) onFrame,
    bool Function() ready,
  ) async {
    final c = _controller;
    if (_closed || c == null || !c.value.isInitialized) {
      return;
    }
    _captureClock.start();
    _frames = _tracker?.frames.listen((frame) {
      if (!_closed && ready()) onFrame(frame);
    });
    await c.startImageStream((image) {
      // Local tracking continues even while Wi-Fi or the word service is busy.
      final localReady = _tracker?.ready == true;
      if (_closed || (!localReady && !ready())) {
        return;
      }
      if (localReady && !_tracker!.canAcceptFrame) return;
      final format = image.format.group;
      final capturedAt = _captureClock.elapsedMilliseconds;
      if (capturedAt - _lastCaptureMs < 25) return;
      if (format != ImageFormatGroup.yuv420 &&
          format != ImageFormatGroup.bgra8888) {
        return;
      }
      _lastCaptureMs = capturedAt;
      if (localReady) {
        _tracker!.submit({
          'format': format == ImageFormatGroup.bgra8888 ? 'bgra8888' : 'yuv420',
          'width': image.width,
          'height': image.height,
          'rotation': _rotation(c),
          'timestamp_ms': capturedAt,
          'encode_frame': ready(),
          'planes': image.planes
              .map(
                (p) => <String, Object>{
                  'row_stride': p.bytesPerRow,
                  'pixel_stride': p.bytesPerPixel ?? 1,
                  // CameraX transfers each plane into a new Dart buffer. Retain
                  // that buffer until the method call completes; do not copy it
                  // a second time on the UI isolate.
                  'bytes': p.bytes,
                },
              )
              .toList(),
        });
        return;
      }
      onFrame(
        CapturedFrame(
          {
            'format': format == ImageFormatGroup.bgra8888
                ? 'bgra8888'
                : 'yuv420',
            'width': image.width,
            'height': image.height,
            'rotation': _rotation(c),
            'planes': image.planes
                .map(
                  (p) => {
                    'row_stride': p.bytesPerRow,
                    'pixel_stride': p.bytesPerPixel ?? 1,
                    'length': p.bytes.length,
                  },
                )
                .toList(),
          },
          image.planes.map((p) => Uint8List.fromList(p.bytes)).toList(),
          timestampMs: capturedAt,
        ),
      );
    });
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _frames?.cancel();
    await _observations?.cancel();
    await _tracker?.close();
    await _local.close();
    final c = _controller;
    _controller = null;
    if (c != null) {
      if (c.value.isStreamingImages) {
        await c.stopImageStream();
      }
      await c.dispose();
    }
  }
}
