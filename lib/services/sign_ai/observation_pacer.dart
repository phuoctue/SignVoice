/// Capture-clock pacing. Claim only when sending a fresh observation, after ACK.
class ObservationPacer {
  static const _periodMs = 1000 / 15;
  double? _nextMs, _lastMs;

  void reset() {
    _nextMs = null;
    _lastMs = null;
  }

  bool claim(num timestampMs) {
    final now = timestampMs.toDouble();
    if (!now.isFinite || now < 0 || (_lastMs != null && now <= _lastMs!)) {
      return false;
    }
    final due = _nextMs ?? now;
    if (now < due - 1) return false;
    // Keep phase through callback jitter; skip missed ticks instead of queuing.
    final missed = now > due ? ((now - due) / _periodMs).floor() : 0;
    _nextMs = due + (missed + 1) * _periodMs;
    _lastMs = now;
    return true;
  }
}
