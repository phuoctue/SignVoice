/// Limits transport work without tying the live preview to inference speed.
/// The media timestamp prevents encoding the same decoded camera frame twice.
class VideoFrameGate {
  double _lastMediaTime = -1;
  int _lastCaptureMs = -1000;

  bool claim(double mediaTime, int nowMs, {required bool ready}) {
    if (!ready || !mediaTime.isFinite || mediaTime < 0) return false;
    // Allow callback jitter around the requested 30 FPS. Requiring exactly
    // 33 ms would discard a new frame delivered 32 ms after its predecessor.
    if (nowMs - _lastCaptureMs < 25 || mediaTime == _lastMediaTime) {
      return false;
    }
    _lastMediaTime = mediaTime;
    _lastCaptureMs = nowMs;
    return true;
  }
}
