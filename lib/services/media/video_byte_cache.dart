import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Small generated sign clips only. Neither a failed request nor an oversized
/// external video can exhaust memory or poison subsequent retries.
class VideoByteCache {
  VideoByteCache({
    http.Client? client,
    this.maxBytes = 8 * 1024 * 1024,
    this.maxFileBytes = 2 * 1024 * 1024,
    this.readDisk,
    this.writeDisk,
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final int maxBytes, maxFileBytes;
  final Future<Uint8List?> Function(Uri)? readDisk;
  final Future<void> Function(Uri, Uint8List)? writeDisk;
  final _cache = <Uri, Uint8List>{};
  final _storedAt = <Uri, DateTime>{};
  final _pending = <Uri, Future<Uint8List>>{};
  int retainedBytes = 0;
  Uint8List? peek(Uri uri) {
    if (DateTime.now().difference(_storedAt[uri] ?? DateTime(1970)) >=
        const Duration(days: 1)) {
      final old = _cache.remove(uri);
      retainedBytes -= old?.length ?? 0;
      _storedAt.remove(uri);
      return null;
    }
    return _cache[uri];
  }

  void seed(Uri uri, Uint8List bytes) {
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        bytes.length > maxFileBytes) {
      return;
    }
    retainedBytes -= _cache.remove(uri)?.length ?? 0;
    while (_cache.isNotEmpty && retainedBytes + bytes.length > maxBytes) {
      final key = _cache.keys.first;
      retainedBytes -= _cache.remove(key)!.length;
      _storedAt.remove(key);
    }
    _cache[uri] = bytes;
    _storedAt[uri] = DateTime.now();
    retainedBytes += bytes.length;
  }

  Future<Uint8List> load(Uri uri) {
    final existing = peek(uri);
    if (existing != null) {
      _cache.remove(uri);
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
    try {
      final bytes = await readDisk?.call(uri);
      if (bytes != null && bytes.isNotEmpty && bytes.length <= maxFileBytes) {
        seed(uri, bytes);
        return bytes;
      }
    } catch (_) {
      /* Cache failure falls back to a fresh request. */
    }
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
    if (bytes.isEmpty ||
        response.contentLength != null &&
            bytes.length != response.contentLength) {
      throw StateError('Dữ liệu media chưa đầy đủ.');
    }
    seed(uri, bytes);
    try {
      await writeDisk?.call(uri, bytes);
    } catch (_) {
      /* Memory cache remains usable. */
    }
    return bytes;
  }
}
