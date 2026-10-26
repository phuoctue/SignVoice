import 'dart:typed_data';

import 'video_source.dart';

VideoSource createVideoSource(Uri original, Uint8List? bytes) =>
    VideoSource(original);
