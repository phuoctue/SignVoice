class VideoSource {
  VideoSource(this.uri, [void Function()? release]) : _release = release;
  final Uri uri;
  void Function()? _release;
  void dispose() {
    final release = _release;
    _release = null;
    release?.call();
  }
}
