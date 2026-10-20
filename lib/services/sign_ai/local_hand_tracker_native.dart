import 'dart:async';

import 'package:flutter/services.dart';

import 'camera_types.dart';

/// Android's detector and JPEG encoder run independently on native threads.
/// This bridge also bounds Dart -> platform messages to active + newest frame.
class NativeHandTracker {
  NativeHandTracker({MethodChannel? methods, Stream<dynamic>? events})
    : _methods = methods ?? const MethodChannel('signvoice/hands'),
      _source =
          events ??
          const EventChannel('signvoice/hands/events').receiveBroadcastStream();
  final MethodChannel _methods;
  final Stream<dynamic> _source;
  final _observations = StreamController<LocalHandObservation>.broadcast();
  final _frames = StreamController<CapturedFrame>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  bool _ready = false, _closed = false, _sending = false;
  bool _awaitingPreview = false;
  int? _submittedStamp;
  Timer? _previewDeadline;
  Map<String, Object>? _latest;
  Stream<LocalHandObservation> get observations => _observations.stream;
  Stream<CapturedFrame> get frames => _frames.stream;
  bool get ready => _ready;
  // Release capture credit on the measured result, not the platform-method ACK.
  // Check this BEFORE copying planes, so a slow detector cannot flood the bridge.
  bool get canAcceptFrame =>
      _ready && !_closed && !_sending && !_awaitingPreview;

  Future<bool> initialize() async {
    _subscription = _source.listen(_event, onError: (_) => _disable());
    try {
      final result = await _methods.invokeMapMethod<String, dynamic>(
        'initialize',
      );
      _ready = !_closed && result?['ready'] == true;
      return _ready;
    } catch (_) {
      _disable();
      return false; // Camera can still use the service's CPU detector.
    }
  }

  void _event(dynamic event) {
    if (_closed || event is! Map) return;
    switch (event['type']) {
      case 'preview':
        final stamp = (event['timestamp'] as num?)?.toInt();
        if (stamp == null ||
            _submittedStamp == null ||
            stamp >= _submittedStamp!) {
          _awaitingPreview = false;
          _previewDeadline?.cancel();
        }
        _observations.add(
          LocalHandObservation(
            event['landmarks'] as List,
            (event['fps'] as num).toDouble(),
            (event['processing_ms'] as num).toDouble(),
            captureSource: event['capture_source'] as String,
            timestampMs: stamp,
            handObservation: event['hand_observation'] is Map
                ? Map<String, dynamic>.from(event['hand_observation'] as Map)
                : null,
          ),
        );
      case 'frame':
        if (!_ready) return;
        final meta = Map<String, Object>.from(event['metadata'] as Map);
        final stamp = (meta.remove('timestamp_ms') as num).toInt();
        _frames.add(
          CapturedFrame(meta, [event['jpeg'] as Uint8List], timestampMs: stamp),
        );
      case 'unavailable':
        _disable();
    }
  }

  void submit(Map<String, Object> frame) {
    if (!_ready || _closed) return;
    _latest = frame;
    if (!_sending) unawaited(_drain());
  }

  Future<void> _drain() async {
    _sending = true;
    try {
      while (_ready && !_closed && _latest != null) {
        final frame = _latest!;
        _latest = null;
        _awaitingPreview = true;
        _submittedStamp = frame['timestamp_ms'] as int?;
        _previewDeadline?.cancel();
        _previewDeadline = Timer(const Duration(seconds: 3), _disable);
        final accepted = await _methods.invokeMethod<bool>('frame', frame);
        if (accepted != true) _disable();
      }
    } catch (_) {
      _disable();
    } finally {
      _sending = false;
    }
  }

  void _disable() {
    _ready = false;
    _awaitingPreview = false;
    _previewDeadline?.cancel();
    _latest = null;
    if (!_closed) {
      unawaited(_methods.invokeMethod<void>('close').catchError((_) {}));
      _observations.add(
        const LocalHandObservation([], 0, 0, captureSource: 'unavailable'),
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ready = false;
    _previewDeadline?.cancel();
    _latest = null;
    await _subscription?.cancel();
    try {
      await _methods.invokeMethod<void>('close');
    } catch (_) {
      /* native optional */
    }
    await _observations.close();
    await _frames.close();
  }
}
