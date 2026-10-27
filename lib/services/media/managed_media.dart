import 'dart:convert';
import 'dart:typed_data';

import '../api/api_config.dart';
import 'video_byte_cache.dart';
import 'media_file_store_stub.dart'
    if (dart.library.io) 'media_file_store_io.dart'
    as storage;

final managedMediaBytes = VideoByteCache(
  maxBytes: 16 * 1024 * 1024,
  maxFileBytes: 4 * 1024 * 1024,
  readDisk: storage.readMediaFile,
  writeDisk: storage.writeMediaFile,
);

bool isManagedMedia(Uri uri) =>
    RegExp(r'^/sign-media/[a-f0-9]{64}(?:-[1-5])?\.(?:mp4|jpg)$')
        .hasMatch(uri.path) &&
    !uri.hasQuery &&
    !uri.hasFragment;

/// Tiny inline thumbnails remove a separate tunnel round-trip per visible card.
/// The normal media URL remains the cache key and fallback for older servers.
void primeImagePreviews(Iterable<Map<String, dynamic>> records) {
  for (final record in records) {
    for (final (urlKey, previewKey) in [
      ('thumbnailUrl', 'thumbnailDataUrl'),
      ('imageUrl', 'imageDataUrl'),
    ]) {
      final url = record[urlKey], preview = record[previewKey];
      if (url is! String ||
          preview is! String ||
          preview.length > 140000 ||
          !preview.startsWith('data:image/jpeg;base64,')) {
        continue;
      }
      final uri = Uri.tryParse(ApiConfig.mediaUrl(url));
      if (uri == null || !isManagedMedia(uri)) continue;
      try {
        final Uint8List bytes = base64Decode(
          preview.substring('data:image/jpeg;base64,'.length),
        );
        managedMediaBytes.seed(uri, bytes);
      } on FormatException {
        /* A bad optional preview must not break the page. */
      }
    }
  }
}
