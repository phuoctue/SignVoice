import 'dart:convert';

import 'camera_types.dart';

/// Bounded RAM only. Pixels require a separate explicit opt-in.
class CameraDiagnostic {
  bool recording = false, truncated = false;
  bool includePixels = false, pixelsTruncated = false;
  final pixels = <Map<String, dynamic>>[];
  int _pixelBytes = 0;
  final messages = <Map<String, dynamic>>[];
  Map<String, dynamic>? workerIdentity;
  int _bytes = 0;
  final _sent = <int, int>{};

  void clear() {
    recording = false;
    truncated = false;
    messages.clear();
    workerIdentity = null;
    _bytes = 0;
    _sent.clear();
    includePixels = false;
    pixelsTruncated = false;
    pixels.clear();
    _pixelBytes = 0;
  }

  void start({bool includePixels = false}) {
    clear();
    this.includePixels = includePixels;
    recording = true;
  }

  void addPixels(CapturedFrame frame) {
    if (!recording || !includePixels || pixelsTruncated) return;
    if (frame.metadata['format'] == 'diagnostic_error') {
      add({'kind': 'pixel_capture_error', 'reason': frame.metadata['reason']});
      return;
    }
    if (frame.metadata['format'] != 'png' || frame.planes.length != 1) return;
    final row = <String, dynamic>{
      for (final key in const [
        'format',
        'width',
        'height',
        'timestamp_ms',
        'rotation',
        'mirrored',
        'pixel_stage',
        'hand_observation',
        'raw_landmarks',
        'raw_handedness',
        'face_anchor',
        'face_anchor_timestamp_ms',
        'snapshot_encode_ms',
        'capture_source',
      ])
        if (frame.metadata.containsKey(key)) key: frame.metadata[key],
      'png_base64': base64Encode(frame.planes.single),
    };
    final encoded = jsonEncode(row);
    if (pixels.length >= 15 || _pixelBytes + encoded.length * 2 > 16000000) {
      pixelsTruncated = true;
      return;
    }
    pixels.add(jsonDecode(encoded) as Map<String, dynamic>);
    _pixelBytes += encoded.length * 2;
  }

  void add(Map<String, dynamic> row) {
    if (!recording || truncated) return;
    final encoded = jsonEncode(row);
    if (messages.length >= 6000 || _bytes + encoded.length * 2 > 12000000) {
      truncated = true;
      recording = false;
      return;
    }
    // Detach from mutable camera/result objects.
    messages.add(jsonDecode(encoded) as Map<String, dynamic>);
    _bytes += encoded.length * 2;
  }

  void sent(int sequence, int now) {
    if (!recording) return;
    _sent[sequence] = now;
    if (_sent.length > 120) _sent.remove(_sent.keys.first);
  }

  void received(Map<String, dynamic> message, int now) {
    if (!recording) return;
    if (message['type'] == 'ready') {
      workerIdentity = message['worker_identity'] as Map<String, dynamic>?;
      return;
    }
    if (message['type'] != 'result') return;
    final sequence = (message['sequence'] as num?)?.toInt();
    final sentAt = _sent.remove(sequence);
    if (sequence != null) _sent.removeWhere((key, _) => key < sequence);
    add({
      'kind': 'result',
      'client_received_ms': now,
      if (sentAt != null && now >= sentAt)
        'send_to_first_result_ms': now - sentAt,
      for (final key in const [
        'sequence',
        'timestamp_ms',
        'publication',
        'hands',
        'mode',
        'confirmed',
        'events',
        'timing',
        'processing_ms',
        'detection_fps',
        'detector_timing',
        'client_detector',
        'inference',
        'prediction_age_ms',
        'landmark_source',
        'dropped_frames',
        'dropped_observations',
        'worker_diagnostic',
      ])
        if (message.containsKey(key)) key: message[key],
    });
  }

  Map<String, dynamic> get summary {
    Map<String, dynamic> distribution(Iterable<num> values) {
      final sorted =
          values
              .map((v) => v.toDouble())
              .where((v) => v.isFinite && v >= 0)
              .toList()
            ..sort();
      if (sorted.isEmpty) {
        return {'samples': 0, 'median_ms': null, 'p95_ms': null};
      }
      double q(double p) {
        final i = (sorted.length - 1) * p;
        final lo = i.floor(), hi = i.ceil();
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (i - lo);
      }

      return {'samples': sorted.length, 'median_ms': q(.5), 'p95_ms': q(.95)};
    }

    return {
      'send_to_first_result': distribution(
        messages.map((m) => m['send_to_first_result_ms']).whereType<num>(),
      ),
      'local_detection': distribution(
        messages
            .where((m) => m['kind'] == 'local')
            .map((m) => m['processing_ms'])
            .whereType<num>(),
      ),
      'encoding': distribution(
        messages
            .where((m) => m['kind'] == 'frame')
            .map((m) => m['encode_ms'])
            .whereType<num>(),
      ),
      'service_context': distribution(
        messages
            .where((m) => m.containsKey('send_to_first_result_ms'))
            .map((m) => (m['timing'] as Map?)?['context_ms'])
            .whereType<num>(),
      ),
      'service_detector': distribution(
        messages
            .where((m) => m.containsKey('send_to_first_result_ms'))
            .map((m) => (m['timing'] as Map?)?['detector_ms'])
            .whereType<num>(),
      ),
      'receive_to_ui_frame': distribution(
        messages.map((m) => m['receive_to_ui_frame_ms']).whereType<num>(),
      ),
      'worker_batch': distribution(
        messages
            .expand(
              (m) =>
                  ((m['worker_diagnostic'] as Map?)?['records'] as List?) ?? [],
            )
            .map((r) => (r as Map)['worker_batch_ms'])
            .whereType<num>(),
      ),
    };
  }

  String export() => jsonEncode({
    'schema': 'signvoice_camera_diagnostic_v1',
    'purpose': 'development_pipeline_only',
    'webcam_accuracy_measured': false,
    'contains_pixels': pixels.isNotEmpty,
    'pixel_capture': {
      'requested': includePixels,
      'scope': 'sampled_exact_detector_input_not_full_video',
      'maximum_fps': 0.5,
      'maximum_frames': 15,
      'truncated': pixelsTruncated,
      'frames': pixels,
    },
    'truncated': truncated,
    'clock_contract': 'Client monotonic arrival times; capture stamps are identifiers. RTT includes queue and processing, not one-way network latency. Worker feature replay excludes camera extraction, transport and UI rendering.',
    'worker_identity': workerIdentity,
    'summary': summary,
    'messages': messages,
  });
}
