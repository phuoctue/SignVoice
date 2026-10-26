import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Small generated sign clips only. Neither a failed request nor an oversized
/// external video can exhaust memory or poison subsequent retries.
class VideoByteCache {
  VideoByteCache({
    http.Client? client,
    this.maxBytes = 8 * 1024 * 1024,
    this.maxFileBytes = 2 * 1024 * 1024,
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final int maxBytes, maxFileBytes;
  final _cache = <Uri, Uint8List>{};
  final _pending = <Uri, Future<Uint8List>>{};
  int retainedBytes = 0;
  Future<Uint8List> load(Uri uri) {
    final existing = _cache.remove(uri);
    if (existing != null) {
      _cache[uri] = existing;
      return Future.value(existing);
    }
    return _pending.putIfAbsent(
      uri,
      () => _download(uri).whenComplete(() {
        _pending.remove(uri);
      }),
    );
  }

  Future<Uint8List> _download(Uri uri) async {
    final response = await _client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > maxFileBytes) {
      await response.stream.listen((_) {}).cancel();
      throw StateError('Không tải được video.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (builder.length + chunk.length > maxFileBytes) {
        throw StateError('Video vượt giới hạn bộ nhớ.');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw StateError('Video không có dữ liệu.');
    if (bytes.length <= maxBytes) {
      while (_cache.isNotEmpty && retainedBytes + bytes.length > maxBytes) {
        retainedBytes -= _cache.remove(_cache.keys.first)!.length;
      }
      _cache[uri] = bytes;
      retainedBytes += bytes.length;
    }
    return bytes;
  }
}
