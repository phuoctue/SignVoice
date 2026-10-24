import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class CapturedFrame {
  CapturedFrame(this.metadata, this.planes, {this.timestampMs});
  final Map<String, Object> metadata;
  final List<Uint8List> planes;
  final int? timestampMs;

  Uint8List packet(int sequence, int timestampMs) {
    final header = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          ...metadata,
          'sequence': sequence,
          'timestamp_ms': this.timestampMs ?? timestampMs,
          'mirrored': false,
        }),
      ),
    );
    final bytes = BytesBuilder(copy: false);
    final size = ByteData(4)..setUint32(0, header.length, Endian.big);
    bytes.add(size.buffer.asUint8List());
    bytes.add(header);
    for (final plane in planes) {
      bytes.add(plane);
    }
    return bytes.takeBytes();
  }
}

abstract class SignCamera {
  bool get front;
  double get aspectRatio;
  Future<void> initialize();
  Widget preview();
  Future<void> start(
    void Function(CapturedFrame) onFrame,
    bool Function() ready,
  );
  Future<void> close();
}

class LocalHandObservation {
  const LocalHandObservation(
    this.landmarks,
    this.fps,
    this.processingMs, {
    this.frame,
    this.captureSource = 'video_callback',
    this.initializationMs,
    this.timestampMs,
    this.captureAgeMs,
    this.handObservation,
  });
  final List<dynamic> landmarks;
  final double fps, processingMs;
  final CapturedFrame? frame;
  final String captureSource;
  final double? initializationMs;
  final int? timestampMs;
  final double? captureAgeMs;
  final Map<String, dynamic>? handObservation;
}

/// GPU observations may carry their matching pixel frame for server extraction.
abstract interface class LocalTrackingCamera {
  Stream<LocalHandObservation> get localTracking;
}

abstract interface class ForegroundTrackingCamera {
  void updateTrackingContext(List<dynamic> anchor, int timestampMs);
}

/// Selects recovery work, without changing the trained feature/model contract.
abstract interface class HandTrackingModeCamera {
  void setTrackingMode(String mode);
}

/// Explicit local-only snapshots of the exact resized detector input.
abstract interface class PixelDiagnosticCamera {
  void setPixelDiagnostic(bool enabled);
  Stream<CapturedFrame> get diagnosticPixels;
}
