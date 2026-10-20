import 'dart:collection';

/// Client timings use one monotonic clock. Server timestamps are not clocks on
/// this device, so they must not be subtracted from client wall time.
class StreamTiming {
  final _sent = <int, int>{};
  final _recent = Queue<int>();
  double encodeMs = 0;
  int? resultMs;

  void sent(int sequence, int nowMs, {num? encodingMs}) {
    _sent[sequence] = nowMs;
    if (_sent.length > 120) _sent.remove(_sent.keys.first);
    _recent.addLast(nowMs);
    while (_recent.isNotEmpty && nowMs - _recent.first > 2000) {
      _recent.removeFirst();
    }
    encodeMs = encodingMs?.toDouble() ?? 0;
  }

  void received(int? sequence, int nowMs) {
    final start = _sent[sequence];
    if (start == null || nowMs < start) return;
    resultMs = nowMs - start;
    _sent.removeWhere((key, _) => key <= sequence!);
  }

  double get sendFps => _recent.length < 2 || _recent.last == _recent.first
      ? 0
      : 1000 * (_recent.length - 1) / (_recent.last - _recent.first);
}
