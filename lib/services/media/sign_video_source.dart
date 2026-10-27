import 'package:flutter/foundation.dart';

import '../api/api_config.dart';
import 'managed_media.dart';
import 'video_source.dart';
import 'video_source_stub.dart'
    if (dart.library.io) 'video_source_io.dart'
    if (dart.library.js_interop) 'video_source_web.dart'
    as platform;

Future<void> prefetchSignVideo(String source) async {
  final uri = Uri.tryParse(ApiConfig.mediaUrl(source));
  if (uri == null || !isManagedMedia(uri) || !uri.path.endsWith('.mp4')) return;
  try {
    await managedMediaBytes.load(uri);
  } catch (_) {
    /* A tap can retry. */
  }
}

Future<VideoSource> openSignVideo(String source) async {
  final uri = Uri.parse(ApiConfig.mediaUrl(source));
  // One full GET avoids repeated range round-trips over a slow tunnel. External
  // and unbounded media keep the platform streaming player.
  if ((kIsWeb ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      isManagedMedia(uri) &&
      uri.path.endsWith('.mp4')) {
    try {
      return await platform.createVideoSource(
        uri,
        await managedMediaBytes.load(uri),
      );
    } catch (_) {
      // Preserve streaming for unusually large clips and temporary cache errors.
      return VideoSource(uri);
    }
  }
  return VideoSource(uri);
}
