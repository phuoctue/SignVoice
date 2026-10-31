import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/api/api_config.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';
import '../../widgets/sign_video_surface.dart';
import '../../services/media/sign_video_source.dart';
import '../../services/media/video_source.dart';
import '../../services/media/managed_media.dart';

const learningLabels = {
  'LEARNING': 'Đang học',
  'REMEMBERED': 'Đã nhớ',
  'REVIEW': 'Ôn tập',
};
const learningColors = {
  'LEARNING': Color(0xFF2563EB),
  'REMEMBERED': Color(0xFF087F6E),
  'REVIEW': Color(0xFFB86E00),
};

class SignPhoto extends StatefulWidget {
  const SignPhoto(
    this.source, {
    super.key,
    this.word = '',
    this.height = 140,
    this.width,
    this.fit = BoxFit.contain,
  });
  final String? source;
  final String word;
  final double height;
  final double? width;
  final BoxFit fit;
  @override
  State<SignPhoto> createState() => _SignPhotoState();
}

class _SignPhotoState extends State<SignPhoto> {
  Future<Uint8List>? _loading;
  @override
  void didUpdateWidget(SignPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _loading = null;
  }

  @override
  Widget build(BuildContext context) {
    final SignPhoto(:source, :word, :height, :width, :fit) = widget;
    Widget fallback({bool loading = false}) {
      final message = loading ? 'Đang tải ảnh' : 'Chưa có ảnh';
      return Semantics(
        image: true,
        label: '$message ký hiệu $word',
        child: Tooltip(
          message: message,
          child: ExcludeSemantics(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              alignment: Alignment.center,
              child: LayoutBuilder(
                builder: (context, constraints) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sign_language_outlined, size: 32),
                    if (constraints.maxWidth >= 100 &&
                        constraints.maxHeight >= 100) ...[
                      const SizedBox(height: 5),
                      Flexible(
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget image;
    final url = source ?? '';
    if (url.isEmpty) {
      image = fallback();
    } else if (url.startsWith('data:image/')) {
      try {
        image = Image.memory(
          base64Decode(url.split(',').last),
          fit: fit,
          semanticLabel: 'Ảnh ký hiệu $word',
          errorBuilder: (_, _, _) => fallback(),
        );
      } catch (_) {
        image = fallback();
      }
    } else {
      final uri = Uri.parse(ApiConfig.mediaUrl(url));
      final decodeWidth = width == null
          ? 640
          : (width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
              64,
              640,
            );
      Widget memory(Uint8List bytes) => Image.memory(
        bytes,
        fit: fit,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        semanticLabel: 'Ảnh ký hiệu $word',
        errorBuilder: (_, _, _) => fallback(),
      );
      final cached = isManagedMedia(uri) ? managedMediaBytes.peek(uri) : null;
      if (cached != null) {
        image = memory(cached);
      } else if (isManagedMedia(uri)) {
        _loading ??= managedMediaBytes.load(uri);
        image = FutureBuilder<Uint8List>(
          future: _loading,
          builder: (_, snapshot) => snapshot.hasData
              ? memory(snapshot.data!)
              : fallback(loading: !snapshot.hasError),
        );
      } else {
        image = Image.network(
          uri.toString(),
          fit: fit,
          cacheWidth: width == null
              ? 640
              : (width * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
                  64,
                  640,
                ),
          gaplessPlayback: true,
          semanticLabel: 'Ảnh ký hiệu $word',
          errorBuilder: (_, _, _) => fallback(),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback(loading: true),
        );
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: ColoredBox(color: const Color(0xFFF2F5FC), child: image),
      ),
    );
  }
}

class LearningPager extends StatelessWidget {
  const LearningPager({
    super.key,
    required this.page,
    required this.pages,
    required this.onPage,
    this.busy = false,
  });
  final int page, pages;
  final bool busy;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.outlined(
          tooltip: 'Trang trước',
          onPressed: !busy && page > 1 ? () => onPage(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text('Trang $page / $pages', textAlign: TextAlign.center),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Trang sau',
          onPressed: !busy && page < pages ? () => onPage(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}

class StageFilters extends StatelessWidget {
  const StageFilters({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    children: [
      for (final entry in {'ALL': 'Tất cả', ...learningLabels}.entries)
        ChoiceChip(
          label: Text(entry.value),
          selected: value == entry.key,
          onSelected: (_) => onChanged(entry.key),
        ),
    ],
  );
}

class LearningSummary extends StatelessWidget {
  const LearningSummary(this.summary, {super.key});
  final LearningRecord summary;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final entry in {
        'learning': 'Đang học',
        'remembered': 'Đã nhớ',
        'review': 'Ôn tập',
      }.entries)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    '${summary[entry.key] ?? 0}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    entry.value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Text('từ', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class LearningWordContent extends StatefulWidget {
  const LearningWordContent(
    this.word, {
    super.key,
    this.showMeaning = true,
    this.hideQuizLabels = false,
    this.quizControls = false,
    this.previewHeight = 230,
    this.showFrames = true,
    this.pauseVideo = false,
  });
  final LearningRecord word;
  final bool showMeaning;
  final bool hideQuizLabels;
  final bool quizControls, showFrames, pauseVideo;
  final double previewHeight;
  @override
  State<LearningWordContent> createState() => _LearningWordContentState();
}

class _LearningWordContentState extends State<LearningWordContent>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  VideoSource? _source;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    primeImagePreviews([widget.word]);
    _frame = _previewFrame(widget.word);
    unawaited(prefetchSignVideo('${widget.word['videoUrl'] ?? ''}'));
  }

  int _previewFrame(LearningRecord word) {
    final images = word['imageUrls'] as List? ?? [];
    final index = images.indexOf(word['thumbnailUrl']);
    return index < 0 ? 0 : index;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _video?.pause();
  }

  bool _loadingVideo = false;
  bool _showQuizVideo = false;
  String? _videoError;
  int _frame = 0;
  double _speed = 1;
  @override
  void didUpdateWidget(covariant LearningWordContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pauseVideo && !oldWidget.pauseVideo) {
      _video?.pause();
    }
    if ((oldWidget.word['_id'] ??
            oldWidget.word['entryId'] ??
            oldWidget.word['videoUrl']) !=
        (widget.word['_id'] ??
            widget.word['entryId'] ??
            widget.word['videoUrl'])) {
      _generation++;
      _video?.dispose();
      _source?.dispose();
      _source = null;
      _video = null;
      _loadingVideo = false;
      _showQuizVideo = false;
      _videoError = null;
      _frame = _previewFrame(widget.word);
      primeImagePreviews([widget.word]);
      unawaited(prefetchSignVideo('${widget.word['videoUrl'] ?? ''}'));
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _video?.dispose();
    _source?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_loadingVideo) return;
    if (_video != null) {
      if (_video!.value.isPlaying && (!widget.quizControls || _showQuizVideo)) {
        await _video!.pause();
      } else {
        await _video!.play();
      }
      if (mounted) setState(() => _showQuizVideo = true);
      return;
    }
    setState(() {
      _loadingVideo = true;
      _videoError = null;
    });
    final generation = ++_generation;
    VideoPlayerController? controller;
    try {
      final source = await openSignVideo('${widget.word['videoUrl']}');
      if (!mounted || generation != _generation) {
        source.dispose();
        return;
      }
      _source = source;
      controller = source.createController();
      _video = controller;
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || _video != controller) return;
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (widget.quizControls && _speed != 1) {
        await controller.setPlaybackSpeed(_speed);
      }
      if (!mounted || generation != _generation) return;
      if (!widget.quizControls || !widget.pauseVideo) {
        await controller.play();
        _showQuizVideo = true;
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        _videoError =
            'Chưa tải được video. Bạn vẫn có thể học bằng chuỗi ảnh bên dưới.';
        await controller?.dispose();
        _source?.dispose();
        _source = null;
        _video = null;
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingVideo = false);
      }
    }
  }

  Future<void> _speedTo(double speed) async {
    final generation = _generation, controller = _video;
    try {
      await controller?.setPlaybackSpeed(speed);
      if (mounted && generation == _generation) {
        setState(() {
          _speed = speed;
          _videoError = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _videoError = 'Thiết bị chưa đổi được tốc độ. Bạn vẫn có thể xem ở tốc độ hiện tại.',
        );
      }
    }
  }

  Future<void> _replay() async {
    final generation = _generation, controller = _video;
    if (controller == null) {
      await _play();
      return;
    }
    try {
      await controller.seekTo(Duration.zero);
      if (!mounted || generation != _generation) return;
      await controller.play();
      if (mounted && generation == _generation) {
        setState(() => _showQuizVideo = true);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _videoError = 'Chưa phát lại được video. Hãy thử lại.');
      }
    }
  }

  Widget _quizMedia(Widget child, {bool thumbnail = false}) {
    if (!widget.hideQuizLabels) return child;
    // Source samples may embed the word in their upper-right corner. Conceal
    // that caption only during a quiz; retain the source logo and original file.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topRight,
                child: FractionallySizedBox(
                  widthFactor: .55,
                  heightFactor: thumbnail ? .34 : .2,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    final images = (word['imageUrls'] as List? ?? [])
        .whereType<String>()
        .toList();
    final image = images.isNotEmpty
        ? images[_frame.clamp(0, images.length - 1)]
        : word['thumbnailUrl'] ?? word['imageUrl'];
    final name = '${word['word'] ?? ''}';
    final ready = _video?.value.isInitialized == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (word['mediaUnavailable'] == true)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Notice('Chưa có ảnh/video mẫu để xem cho từ này.'),
          ),
        if (ready && (!widget.quizControls || _showQuizVideo))
          _quizMedia(
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: widget.quizControls
                  ? SizedBox(
                      height: widget.previewHeight,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _video!.value.aspectRatio,
                          child: SignVideoSurface(_video!),
                        ),
                      ),
                    )
                  : AspectRatio(
                      aspectRatio: _video!.value.aspectRatio,
                      child: SignVideoSurface(_video!),
                    ),
            ),
          )
        else
          _quizMedia(
            SignPhoto(
              image as String?,
              word: name,
              height: widget.previewHeight,
            ),
          ),
        if ('${word['videoUrl'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadingVideo ? null : _play,
            icon: Icon(
              _video?.value.isPlaying == true
                  ? Icons.pause
                  : Icons.play_circle_outline,
            ),
            label: Text(
              _loadingVideo
                  ? 'Đang tải video...'
                  : _video?.value.isPlaying == true
                  ? 'Tạm dừng video'
                  : 'Xem video ký hiệu',
            ),
          ),
        ],
        if (_videoError != null) Notice(_videoError!),
        if (widget.quizControls && '${word['videoUrl'] ?? ''}'.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _loadingVideo ? null : _replay,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                icon: const Icon(Icons.replay),
                label: const Text('Xem lại'),
              ),
              for (final speed in [.5, 1.0])
                ChoiceChip(
                  label: Text(speed == .5 ? '0,5×' : '1×'),
                  tooltip: speed == .5
                      ? 'Phát chậm một nửa'
                      : 'Tốc độ bình thường',
                  selected: _speed == speed,
                  onSelected: _loadingVideo ? null : (_) => _speedTo(speed),
                ),
            ],
          ),
        if (widget.showFrames && images.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            'Thứ tự động tác · Ảnh ${_frame + 1}/${images.length}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => Semantics(
                button: true,
                label: 'Xem ảnh ${i + 1}',
                child: InkWell(
                  onTap: () {
                    if (widget.quizControls) _video?.pause();
                    setState(() {
                      _frame = i;
                      if (widget.quizControls) _showQuizVideo = false;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _frame == i
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _quizMedia(
                      SignPhoto(
                        images[i],
                        width: 66,
                        height: 68,
                        word: '$name, bước ${i + 1}',
                      ),
                      thumbnail: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (widget.showMeaning) ...[
          const SizedBox(height: 18),
          const Heading('Ý nghĩa', size: 17),
          const SizedBox(height: 6),
          BodyText('${word['definition'] ?? ''}'),
          if ('${word['usageExample'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            const Heading('Ví dụ sử dụng', size: 17),
            const SizedBox(height: 6),
            BodyText('“${word['usageExample']}”'),
          ],
          if ('${word['notes'] ?? ''}'.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Nguồn & ghi chú'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: BodyText('${word['notes']}'),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

Future<void> showLearningWord(BuildContext context, LearningRecord word) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${word['word']}'),
          leading: IconButton(
            tooltip: 'Đóng',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: LearningWordContent(word),
        ),
      ),
    ),
  );
}
