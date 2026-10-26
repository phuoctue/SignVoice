import 'package:flutter/foundation.dart';

import '../api/api_config.dart';
import 'video_byte_cache.dart';
import 'video_source.dart';
import 'video_source_stub.dart'
    if (dart.library.js_interop) 'video_source_web.dart'
    as platform;

final _clips = VideoByteCache();
Future<VideoSource> openSignVideo(String source) async {
  final uri = Uri.parse(ApiConfig.mediaUrl(source));
  // One full GET avoids repeated range round-trips over a slow tunnel. External
  // and unbounded media keep the platform streaming player.
  if (kIsWeb && RegExp(r'^/sign-media/[a-f0-9]{64}\.mp4$').hasMatch(uri.path)) {
    return platform.createVideoSource(uri, await _clips.load(uri));
  }
  return VideoSource(uri);
}
