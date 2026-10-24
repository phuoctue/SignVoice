import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'camera_types.dart';

@JS('MediaStreamTrackProcessor')
extension type _TrackProcessor._(JSObject _) implements JSObject {
  external factory _TrackProcessor(JSObject options);
  external web.ReadableStream get readable;
}

class BrowserHandTracker {
  final _events = StreamController<LocalHandObservation>.broadcast();
  final _frames = StreamController<CapturedFrame>.broadcast();
  final _diagnosticPixels = StreamController<CapturedFrame>.broadcast();
  bool _pixelDiagnostic = false;
  bool get pixelDiagnostic => _pixelDiagnostic;
  set pixelDiagnostic(bool enabled) {
    _pixelDiagnostic = enabled;
    if (!enabled && _ready) {
      _worker?.postMessage({'type': 'stop_diagnostic_pixels'}.jsify());
    }
  }

  Stream<CapturedFrame> get diagnosticPixels => _diagnosticPixels.stream;
  web.Worker? _worker;
  bool _ready = false, _busy = false, _closed = false;
  double _lastVideoTime = -1;
  Timer? _deadline;
  web.MediaStreamTrack? _sourceTrack;
  web.MediaStreamTrack? _cameraTrack;
  int Function()? _timestamp;
  bool _streaming = false, _initializing = false, _firstPreview = false;
  double? _initializationMs;
  final _startupClock = Stopwatch();
  String _startupPhase = 'idle';
  String? _startupFailure, _failedPhase;
  Map<String, Object> get startupDiagnostics {
    final diagnostic = <String, Object>{
      'phase': _startupPhase,
      'elapsed_ms': _startupClock.elapsedMilliseconds,
    };
    final failure = _startupFailure, failedPhase = _failedPhase;
    if (failure != null) {
      diagnostic['reason'] = failure;
    }
    if (failedPhase != null) {
      diagnostic['failed_phase'] = failedPhase;
    }
    return diagnostic;
  }

  Stream<LocalHandObservation> get stream => _events.stream;
  Stream<CapturedFrame> get frames => _frames.stream;
  bool get ready => _ready;
  bool get initializing => _initializing;

  void updateContext(List<dynamic> anchor, int timestampMs) {
    if (_ready && !_closed && anchor.length == 4) {
      _worker?.postMessage(
        {'type': 'context', 'anchor': anchor, 'timestamp': timestampMs}.jsify(),
      );
    }
  }

  void initialize({
    web.MediaStreamTrack? track,
    int Function()? timestamp,
    int targetHands = 2,
  }) {
    _startupClock.start();
    _startupPhase = 'worker';
    _initializing = true;
    _events.add(
      const LocalHandObservation([], 0, 0, captureSource: 'initializing'),
    );
    _cameraTrack = track;
    _timestamp = timestamp;
    try {
      final worker = web.Worker(
        Uri.base.resolve('signvoice_hand_worker.js?v=8.7').toString().toJS,
        web.WorkerOptions(type: 'classic'),
      );
      _worker = worker;
      worker.onmessage = ((web.MessageEvent event) {
        if (_closed || !identical(_worker, worker)) return;
        final packet = event.data as JSObject;
        final data = jsonDecode(
          packet.getProperty<JSString>('meta'.toJS).toDart,
        ) as Map<String, dynamic>;
        if (data['type'] == 'init_progress') {
          _startupPhase = data['phase']?.toString() ?? 'initializing';
          return;
        } else if (data['type'] == 'ready') {
          _startupPhase = 'ready';
          _startupClock.stop();
          _initializing = false;
          _initializationMs = (data['init_ms'] as num?)?.toDouble();
          _deadline?.cancel();
          _ready = true;
          _startupPhase = 'first_frame';
          _attachTrack();
        } else if (data['type'] == 'preview') {
          _firstPreview = true;
          _startupPhase = 'live';
          // Detection finishes before JPEG. Release the capture gate now so a
          // slow encoder/network cannot reduce measured-landmark cadence.
          _deadline?.cancel();
          _busy = false;
          if (_streaming) {
            _deadline = Timer(
              Duration(seconds: _firstPreview ? 3 : 10),
              _disable,
            );
          }
          _events.add(
            LocalHandObservation(
              data['landmarks'] as List,
              (data['fps'] as num).toDouble(),
              (data['processing_ms'] as num).toDouble(),
              captureSource:
                  data['capture_source'] as String? ?? 'video_callback',
              initializationMs: _initializationMs,
              handObservation:
                  data['hand_observation'] as Map<String, dynamic>?,
            ),
          );
        } else if (data['type'] == 'diagnostic_error') {
          // A local diagnostic failure must not stop recognition.
          _diagnosticPixels.add(
            CapturedFrame({
              'format': 'diagnostic_error',
              'reason': data['reason']?.toString() ?? 'png_failed',
            }, []),
          );
          return;
        } else if (data['type'] == 'diagnostic_pixels') {
          if (pixelDiagnostic) {
            _diagnosticPixels.add(
              CapturedFrame(
                {
                  for (final entry in data.entries)
                    if (entry.value != null) entry.key: entry.value as Object,
                },
                [
                  packet
                      .getProperty<JSArrayBuffer>('jpeg'.toJS)
                      .toDart
                      .asUint8List(),
                ],
                timestampMs: data['timestamp_ms'] as int,
              ),
            );
          }
        } else if (data['type'] == 'tracking') {
          _frames.add(
            CapturedFrame(
              {
                'format': 'jpeg',
                'width': data['width'] as int,
                'height': data['height'] as int,
                'rotation': 0,
                'encode_ms': data['encode_ms'] as num,
                'hand_observation':
                    data['hand_observation'] as Map<String, dynamic>,
                if (data['hand_history'] is List)
                  'hand_history': data['hand_history'] as List,
              },
              [
                packet
                    .getProperty<JSArrayBuffer>('jpeg'.toJS)
                    .toDart
                    .asUint8List(),
              ],
              timestampMs: data['timestamp'] as int,
            ),
          );
        } else {
          _disable(data['reason']?.toString() ?? 'unexpected_worker_message');
        }
      }).toJS;
      worker.onerror = ((web.Event event) {
        if (identical(_worker, worker)) _disable('worker_error');
      }).toJS;
      worker.postMessage(
        {
          'type': 'init',
          'early_preview': true,
          'independent_encode': true,
          'target_hands': targetHands,
          'temporal_history': targetHands == 1,
          'live_observations': true,
          'startup_progress': true,
          'enable_recovery': false,
          'diagnostic_pixels': pixelDiagnostic,
        }.jsify(),
      );
      // A slow public download is different from a stalled frame. Keep local
      // initialization alive while CPU fallback provides interim observations.
      _deadline = Timer(const Duration(seconds: 120), _disable);
    } catch (_) {
      _disable('worker_start_failed');
    }
  }

  void _attachTrack() {
    // A native frame stream keeps capture independent of Flutter repaint work.
    // Chrome exposes this on Window; other browsers keep the bitmap fallback.
    if (_cameraTrack == null ||
        !globalContext.has('MediaStreamTrackProcessor')) {
      return;
    }
    try {
      _sourceTrack = _cameraTrack!.clone();
      final processor = _TrackProcessor(
        {'track': _sourceTrack, 'maxBufferSize': 1}.jsify()! as JSObject,
      );
      final readable = processor.readable;
      _worker!.postMessage(
        {
          'type': 'camera_stream',
          'readable': readable,
          'timestamp': _timestamp!(),
        }.jsify(),
        [readable].toJS,
      );
      _streaming = true;
      _deadline = Timer(Duration(seconds: _firstPreview ? 3 : 10), _disable);
    } catch (_) {
      _sourceTrack?.stop();
      _sourceTrack = null;
    }
  }

  Future<void> track(web.HTMLVideoElement video, int timestamp) async {
    if (_closed ||
        !_ready ||
        _streaming ||
        _busy ||
        video.readyState < 2 ||
        video.currentTime == _lastVideoTime) {
      return;
    }
    _lastVideoTime = video.currentTime;
    _busy = true;
    _deadline = Timer(Duration(seconds: _firstPreview ? 3 : 10), _disable);
    try {
      final bitmap = await web.window.createImageBitmap(video).toDart;
      if (_closed || _worker == null) {
        bitmap.close();
        return;
      }
      _worker!.postMessage(
        {'type': 'frame', 'frame': bitmap, 'timestamp': timestamp}.jsify(),
        [bitmap].toJS,
      );
    } catch (_) {
      _disable('bitmap_capture_failed');
    }
  }

  void _disable([String reason = 'detector_timeout']) {
    if (!_closed) {
      _failedPhase = _startupPhase;
      _startupPhase = 'fallback';
      _startupFailure = reason.length > 240 ? reason.substring(0, 240) : reason;
      _startupClock.stop();
    }
    _deadline?.cancel();
    _ready = false;
    _initializing = false;
    _streaming = false;
    _sourceTrack?.stop();
    _sourceTrack = null;
    _busy = false;
    _worker?.terminate();
    _worker = null;
    if (!_closed) {
      _events.add(
        const LocalHandObservation([], 0, 0, captureSource: 'unavailable'),
      );
    }
  }

  Future<void> close() async {
    _closed = true;
    _disable();
    await _events.close();
    await _frames.close();
    await _diagnosticPixels.close();
  }
}
