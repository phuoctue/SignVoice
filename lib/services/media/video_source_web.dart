import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'video_source.dart';

Future<VideoSource> createVideoSource(Uri original, Uint8List? bytes) async {
  if (bytes == null) return VideoSource(original);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'video/mp4'),
  );
  final url = web.URL.createObjectURL(blob);
  return VideoSource(Uri.parse(url), () => web.URL.revokeObjectURL(url));
}
