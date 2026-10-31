import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../features/learning/learning_widgets.dart';
import '../services/media/sign_video_source.dart';
import '../services/media/video_source.dart';
import 'sign_video_surface.dart';

/// Public previews share one playback owner, including across route changes.
final _previewOwner = ValueNotifier<Object?>(null);

class PublicSignPreview extends StatefulWidget {
  const PublicSignPreview({
    super.key,
    required this.word,
    this.height = 220,
    this.autoplay = false,
    this.loading = false,
    this.controls = true,
  });
  final Map<String, dynamic> word;
  final double height;
  final bool autoplay, loading, controls;
  @override
  State<PublicSignPreview> createState() => _PublicSignPreviewState();
}

class _PublicSignPreviewState extends State<PublicSignPreview>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  VideoSource? _source;
  ScrollPosition? _scroll;
  Timer? _hoverDelay;
  int _generation = 0;
  bool _hover = false, _opening = false, _autoStarted = false;
  String? _error;

  String get name => '${widget.word['word'] ?? ''}';
  String get url => '${widget.word['videoUrl'] ?? ''}';
  bool get reduce => MediaQuery.disableAnimationsOf(context);
  bool get visible {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final top = box.localToGlobal(Offset.zero).dy;
    return top < MediaQuery.sizeOf(context).height - 40 &&
        top + box.size.height > 80;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _previewOwner.addListener(_ownerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_checkVisibility);
      _scroll = scroll;
      _scroll?.addListener(_checkVisibility);
    }
    if (reduce) _stop(rebuild: false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void didUpdateWidget(PublicSignPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loading != widget.loading ||
        oldWidget.word['videoUrl'] != widget.word['videoUrl'] ||
        oldWidget.word['word'] != widget.word['word']) {
      _stop(rebuild: false);
      _autoStarted = false;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  void _ownerChanged() {
    if (_previewOwner.value != this) _stop();
  }

  void _checkVisibility() {
    if (!mounted) return;
    if (!visible) {
      if (_video != null || _opening) _stop();
      return;
    }
    if (widget.autoplay &&
        !widget.loading &&
        !_autoStarted &&
        !reduce &&
        url.isNotEmpty &&
        _previewOwner.value == null) {
      _autoStarted = true;
      unawaited(_play());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  void _stop({bool rebuild = true}) {
    _hoverDelay?.cancel();
    final controller = _video, source = _source;
    final changed = controller != null || _opening;
    _generation++;
    _video = null;
    _source = null;
    _opening = false;
    if (controller != null) {
      unawaited(controller.dispose().whenComplete(() => source?.dispose()));
    } else {
      source?.dispose();
    }
    if (_previewOwner.value == this) _previewOwner.value = null;
    if (changed && mounted && rebuild) setState(() {});
  }

  Future<void> _play() async {
    if (widget.loading ||
        _opening ||
        _video != null ||
        url.isEmpty ||
        !visible) {
      return;
    }
    _previewOwner.value = this;
    final request = ++_generation;
    setState(() {
      _opening = true;
      _error = null;
    });
    VideoPlayerController? controller;
    VideoSource? source;
    try {
      source = await openSignVideo(url);
      if (!mounted || request != _generation) {
        source.dispose();
        return;
      }
      controller = source.createController();
      _source = source;
      _video = controller;
      await controller.initialize().timeout(const Duration(seconds: 15));
      if (!mounted || request != _generation) return;
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted || request != _generation) return;
      await controller.play();
    } catch (_) {
      if (mounted && request == _generation) {
        _stop(rebuild: false);
        _error = 'Chưa phát được video. Bạn vẫn xem được ảnh ký hiệu.';
      }
    } finally {
      if (mounted && request == _generation) {
        setState(() => _opening = false);
      } else if (mounted && _error != null) {
        setState(() {});
      }
    }
  }

  void _hoverTo(bool hover) {
    setState(() => _hover = hover);
    _hoverDelay?.cancel();
    if (hover && !reduce && url.isNotEmpty) {
      _hoverDelay = Timer(const Duration(milliseconds: 320), () {
        if (mounted && _hover) unawaited(_play());
      });
    } else if (!hover && !widget.autoplay) {
      _stop();
    }
  }

  @override
  void dispose() {
    _previewOwner.removeListener(_ownerChanged);
    WidgetsBinding.instance.removeObserver(this);
    _scroll?.removeListener(_checkVisibility);
    _stop(rebuild: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final images = List<String>.from(widget.word['imageUrls'] as List? ?? []);
    final alternate = _hover && !reduce && images.length > 1 ? images[1] : null;
    final playing = _video?.value.isInitialized == true;
    return MouseRegion(
      onEnter: (_) => _hoverTo(true),
      onExit: (_) => _hoverTo(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.loading)
                  const PublicPreviewSkeleton()
                else
                  SignPhoto(
                    alternate ?? widget.word['thumbnailUrl'] as String?,
                    word: name,
                    height: widget.height,
                  ),
                if (playing)
                  ColoredBox(
                    color: scheme.surfaceContainerLow,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _video!.value.aspectRatio,
                        child: SignVideoSurface(_video!),
                      ),
                    ),
                  ),
                if (_opening)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (_error != null)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      color: scheme.errorContainer,
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.controls)
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.centerRight,
                child: url.isEmpty || widget.loading
                    ? const SizedBox.shrink()
                    : Tooltip(
                        message: playing || _opening
                            ? 'Dừng xem trước $name'
                            : 'Xem trước video $name',
                        child: TextButton.icon(
                          onPressed: playing || _opening
                              ? _stop
                              : () => unawaited(_play()),
                          icon: Icon(
                            playing || _opening
                                ? Icons.pause
                                : Icons.play_arrow,
                            size: 18,
                          ),
                          label: Text(
                            playing || _opening
                                ? 'Dừng xem trước'
                                : 'Xem trước',
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class PublicPreviewSkeleton extends StatelessWidget {
  const PublicPreviewSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Đang tải mẫu ký hiệu',
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Container(
            width: 76,
            height: 110,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
      ),
    );
  }
}
