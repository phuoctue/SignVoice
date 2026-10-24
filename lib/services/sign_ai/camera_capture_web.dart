import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'camera_types.dart';
import 'media_access_error.dart';
import 'video_frame_gate.dart';
import 'local_hand_tracker_web.dart';

SignCamera createSignCamera({required bool front}) => BrowserSignCamera(front);

class BrowserSignCamera
    implements
        SignCamera,
        LocalTrackingCamera,
        ForegroundTrackingCamera,
        HandTrackingModeCamera,
        PixelDiagnosticCamera {
  BrowserSignCamera(this.front);
  @override
  final bool front;
  static int _nextId = 0;
  final String _viewType = 'signvoice-camera-${_nextId++}';
  final web.HTMLVideoElement _video = web.HTMLVideoElement();
  final web.HTMLCanvasElement _canvas = web.HTMLCanvasElement();
  web.MediaStream? _stream;
  Timer? _timer;
  int? _videoCallback;
  bool _closed = false, _encoding = false;
  final _captureClock = Stopwatch();
  final _frameGate = VideoFrameGate();
  final _localTracker = BrowserHandTracker();
  @override
  void setPixelDiagnostic(bool enabled) =>
      _localTracker.pixelDiagnostic = enabled;
  @override
  Stream<CapturedFrame> get diagnosticPixels => _localTracker.diagnosticPixels;
  StreamSubscription<CapturedFrame>? _gpuSubscription;
  int _lastDelivered = -1;
  int _lastStartupFallback = -1000;
  int _targetHands = 2;
  @override
  void setTrackingMode(String mode) =>
      _targetHands = (mode == 'digits' || mode == 'letters') ? 1 : 2;
  @override
  Stream<LocalHandObservation> get localTracking => _localTracker.stream;
  @override
  void updateTrackingContext(List<dynamic> anchor, int timestampMs) =>
      _localTracker.updateContext(anchor, timestampMs);
  late final web.CanvasRenderingContext2D _context = _canvas.context2D;
  @override
  double get aspectRatio =>
      _video.videoHeight > 0 ? _video.videoWidth / _video.videoHeight : 4 / 3;

  @override
  Future<void> initialize() async {
    if (!web.window.isSecureContext) {
      throw mediaAccessError('insecure');
    }
    try {
      _video
        ..autoplay = true
        ..muted = true;
      _video.setAttribute('playsinline', 'true');
      _video.style
        ..width = '100%'
        ..height = '100%'
        ..objectFit = 'contain'
        ..transform = front ? 'scaleX(-1)' : 'none';
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              audio: false.toJS,
              video: {
                'facingMode': {'ideal': front ? 'user' : 'environment'},
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 30, 'max': 30},
              }.jsify()!,
            ),
          )
          .toDart;
      if (_closed) {
        for (final t in stream.getTracks().toDart) {
          t.stop();
        }
        return;
      }
      _stream = stream;
      _video.srcObject = stream;
      await _video.play().toDart;
      ui_web.platformViewRegistry.registerViewFactory(
        _viewType,
        (int id) => _video,
      );
    } catch (error) {
      for (final track
          in _stream?.getTracks().toDart ?? <web.MediaStreamTrack>[]) {
        track.stop();
      }
      _video.srcObject = null;
      _stream = null;
      throw mediaAccessError(error.toString());
    }
  }

  @override
  Widget preview() => HtmlElementView(viewType: _viewType);

  @override
  Future<void> start(
    void Function(CapturedFrame) onFrame,
    bool Function() ready,
  ) async {
    _captureClock.start();
    void deliver(CapturedFrame frame) {
      final stamp = frame.timestampMs!;
      if (!_closed && ready() && stamp > _lastDelivered) {
        _lastDelivered = stamp;
        onFrame(frame);
      }
    }

    _gpuSubscription = _localTracker.frames.listen(deliver);
    _localTracker.initialize(
      targetHands: _targetHands,
      track: _stream?.getVideoTracks().toDart.first,
      timestamp: () => _captureClock.elapsedMilliseconds,
    );
    Future<void> capture() async {
      if (_closed ||
          _localTracker.ready ||
          _encoding ||
          _video.videoWidth == 0 ||
          _video.readyState < 2) {
        return;
      }
      final capturedAt = _captureClock.elapsedMilliseconds;
      // Leave CPU capacity for cold WASM/GPU startup; keep the service alive.
      if (_localTracker.initializing &&
          (capturedAt < 1500 || capturedAt - _lastStartupFallback < 500)) {
        return;
      }
      if (!_frameGate.claim(_video.currentTime, capturedAt, ready: ready())) {
        return;
      }
      _lastStartupFallback = capturedAt;
      _encoding = true;
      try {
        final width = _video.videoWidth.clamp(1, 640);
        final height = (_video.videoHeight * width / _video.videoWidth).round();
        // Assigning dimensions clears the canvas and resets its drawing state.
        // Only resize when the device actually changes resolution/orientation.
        if (_canvas.width != width) _canvas.width = width;
        if (_canvas.height != height) _canvas.height = height;
        _context.drawImage(_video, 0, 0, width, height);
        final completer = Completer<web.Blob?>();
        _canvas.toBlob(
          ((web.Blob? blob) {
            completer.complete(blob);
          }).toJS,
          'image/jpeg',
          0.78.toJS,
        );
        final blob = await completer.future;
        if (blob == null || _closed) {
          return;
        }
        final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
        if (!_closed && !_localTracker.ready && ready()) {
          deliver(
            CapturedFrame(
              {
                'format': 'jpeg',
                'width': width,
                'height': height,
                'rotation': 0,
                'encode_ms': _captureClock.elapsedMilliseconds - capturedAt,
                'client_detector_startup': _localTracker.startupDiagnostics,
              },
              [bytes],
              timestampMs: capturedAt,
            ),
          );
        }
      } finally {
        _encoding = false;
      }
    }

    if (_video.has('requestVideoFrameCallback')) {
      // Schedule from decoded frames, not timer ticks. Encoding and transport
      // may skip a frame; neither may hold up the browser's live preview.
      late final JSFunction callback;
      callback = ((JSNumber now, JSObject metadata) {
        if (_closed) return;
        _videoCallback = _video.requestVideoFrameCallback(callback);
        unawaited(
          _localTracker.track(_video, _captureClock.elapsedMilliseconds),
        );
        unawaited(capture());
      }).toJS;
      _videoCallback = _video.requestVideoFrameCallback(callback);
    } else {
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        unawaited(
          _localTracker.track(_video, _captureClock.elapsedMilliseconds),
        );
        unawaited(capture());
      });
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    if (_videoCallback != null) {
      _video.cancelVideoFrameCallback(_videoCallback!);
      _videoCallback = null;
    }
    _captureClock.stop();
    await _gpuSubscription?.cancel();
    await _localTracker.close();
    for (final t in _stream?.getTracks().toDart ?? <web.MediaStreamTrack>[]) {
      t.stop();
    }
    _video.srcObject = null;
    _stream = null;
  }
}
