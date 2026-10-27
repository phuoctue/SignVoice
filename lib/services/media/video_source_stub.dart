import 'dart:typed_data';

import 'video_source.dart';

Future<VideoSource> createVideoSource(Uri original, Uint8List? bytes) async =>
    VideoSource(original);
