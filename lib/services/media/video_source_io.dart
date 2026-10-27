import 'dart:io';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'media_file_store_io.dart';
import 'video_source.dart';

Future<VideoSource> createVideoSource(Uri original, Uint8List? bytes) async {
  if (bytes == null) return VideoSource(original);
  await mediaFiles.write(original, bytes);
  final file = mediaFiles.file(original);
  if (file == null || !await file.exists()) return VideoSource(original);
  return VideoSource(
    file.uri,
    null,
    () => VideoPlayerController.file(File.fromUri(file.uri)),
  );
}
