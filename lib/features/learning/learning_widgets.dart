import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/api/api_config.dart';
import '../../services/learning/learning_service.dart';
import '../../widgets/ui.dart';

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

class SignPhoto extends StatelessWidget {
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
  Widget build(BuildContext context) {
    Widget fallback({bool loading = false}) => Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sign_language_outlined, size: 32),
          const SizedBox(height: 5),
          Text(
            loading ? 'Đang tải ảnh' : 'Chưa có ảnh',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
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
      image = Image.network(
        ApiConfig.mediaUrl(url),
        fit: fit,
        semanticLabel: 'Ảnh ký hiệu $word',
        errorBuilder: (_, _, _) => fallback(),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback(loading: true),
      );
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
                color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Text('từ', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class LearningWordContent extends StatefulWidget {
  const LearningWordContent(this.word, {super.key, this.showMeaning = true});
  final LearningRecord word;
  final bool showMeaning;
  @override
  State<LearningWordContent> createState() => _LearningWordContentState();
}

class _LearningWordContentState extends State<LearningWordContent> {
  VideoPlayerController? _video;
  bool _loadingVideo = false;
  String? _videoError;
  int _frame = 0;
  @override
  void didUpdateWidget(covariant LearningWordContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word['_id'] != widget.word['_id']) {
      _video?.dispose();
      _video = null;
      _loadingVideo = false;
      _videoError = null;
      _frame = 0;
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    if (_video != null) {
      if (_video!.value.isPlaying) {
        await _video!.pause();
      } else {
        await _video!.play();
      }
      if (mounted) setState(() {});
      return;
    }
    setState(() {
      _loadingVideo = true;
      _videoError = null;
    });
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(ApiConfig.mediaUrl('${widget.word['videoUrl']}')),
    );
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted || _video != controller) return;
      await controller.setLooping(true);
      await controller.play();
    } catch (_) {
      if (mounted && _video == controller) {
        _videoError =
            'Chưa tải được video. Bạn vẫn có thể học bằng chuỗi ảnh bên dưới.';
        await controller.dispose();
        _video = null;
      }
    } finally {
      if (mounted) setState(() => _loadingVideo = false);
    }
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
        if (ready)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: _video!.value.aspectRatio,
              child: VideoPlayer(_video!),
            ),
          )
        else
          SignPhoto(image as String?, word: name, height: 230),
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
        if (images.length > 1) ...[
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
                  onTap: () => setState(() => _frame = i),
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
                    child: SignPhoto(
                      images[i],
                      width: 66,
                      height: 68,
                      word: '$name, bước ${i + 1}',
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
