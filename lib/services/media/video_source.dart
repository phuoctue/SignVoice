import 'package:video_player/video_player.dart';

class VideoSource {
  VideoSource(
    this.uri, [
    void Function()? release,
    VideoPlayerController Function()? controller,
  ]) : _release = release,
       _controller = controller;
  final Uri uri;
  void Function()? _release;
  final VideoPlayerController Function()? _controller;
  VideoPlayerController createController() =>
      _controller?.call() ?? VideoPlayerController.networkUrl(uri);
  void dispose() {
    final release = _release;
    _release = null;
    release?.call();
  }
}
