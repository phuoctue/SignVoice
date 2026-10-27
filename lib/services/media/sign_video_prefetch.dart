import 'dart:async';

import 'sign_video_source.dart';

/// One speculative download at a time. Navigation replaces the waiting window
/// so rapid Next/Previous taps never queue the entire sentence for download.
class SignVideoPrefetch {
  SignVideoPrefetch({this.load = prefetchSignVideo});
  final Future<void> Function(String) load;
  final _done = <String>{};
  List<String> _waiting = [];
  String? _active;
  bool _running = false, _disposed = false;

  void warm(Iterable<String> sources) {
    if (_disposed) return;
    _waiting = sources
        .where(
          (url) => url.isNotEmpty && url != _active && !_done.contains(url),
        )
        .toSet()
        .take(2)
        .toList();
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    while (!_disposed && _waiting.isNotEmpty) {
      final url = _active = _waiting.removeAt(0);
      try {
        await load(url);
        if (_done.length >= 64) _done.remove(_done.first);
        _done.add(url);
      } catch (_) {
        /* Foreground playback can retry. */
      }
      _active = null;
    }
    _running = false;
  }

  void dispose() {
    _disposed = true;
    _waiting.clear();
  }
}
