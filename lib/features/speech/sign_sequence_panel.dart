import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';
import '../../services/media/sign_video_source.dart';
import '../../services/media/video_source.dart';
import '../../services/media/sign_video_prefetch.dart';
import '../learning/learning_widgets.dart' show SignPhoto;
import '../../widgets/sign_video_surface.dart';

typedef SequenceLoader = Future<Map<String, dynamic>> Function(String text);

Future<Map<String, dynamic>> loadSignSequence(String text) async {
  final response = await ApiClient.instance.post(
    '/sign-sequence',
    body: {'text': text},
    requiresAuth: true,
  );
  final data = Map<String, dynamic>.from(response['data'] as Map);
  Map<String, dynamic> resolve(dynamic value) {
    final segment = Map<String, dynamic>.from(value as Map);
    for (final field in ['thumbnailUrl', 'videoUrl']) {
      if (segment[field] is String) {
        segment[field] = ApiConfig.mediaUrl(segment[field] as String);
      }
    }
    if (segment['imageUrls'] is List) {
      segment['imageUrls'] = (segment['imageUrls'] as List)
          .whereType<String>()
          .map(ApiConfig.mediaUrl)
          .toList();
    }
    if (segment['letters'] is List) {
      segment['letters'] = (segment['letters'] as List).map(resolve).toList();
    }
    return segment;
  }

  data['segments'] = (data['segments'] as List).map(resolve).toList();
  return data;
}

class SignSequencePanel extends StatefulWidget {
  const SignSequencePanel({
    super.key,
    required this.text,
    this.loader = loadSignSequence,
  });
  final String text;
  final SequenceLoader loader;
  @override
  State<SignSequencePanel> createState() => _SignSequencePanelState();
}

class _SignSequencePanelState extends State<SignSequencePanel> {
  List<Map<String, dynamic>>? segments;
  bool loading = false;
  String? error;
  int request = 0;
  SignVideoPrefetch _prefetch = SignVideoPrefetch();

  @override
  void dispose() {
    request++;
    _prefetch.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> playbackItems(List<Map<String, dynamic>> items) =>
      [
        for (final item in items)
          if (item['type'] == 'fingerspelling')
            for (final letter in item['letters'] as List)
              {
                ...Map<String, dynamic>.from(letter),
                'text': '${letter['text']} · đánh vần “${item['text']}”',
              }
          else
            item,
      ];

  @override
  void didUpdateWidget(covariant SignSequencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _prefetch.dispose();
      _prefetch = SignVideoPrefetch();
      request++;
      segments = null;
      error = null;
      loading = false;
    }
  }

  Future<void> load() async {
    final version = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.loader(widget.text);
      if (!mounted || version != request) return;
      setState(
        () => segments = (data['segments'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList(),
      );
      _prefetch.warm(
        playbackItems(segments!)
            .where((item) => item['type'] == 'sign')
            .take(2)
            .map((item) => '${item['videoUrl'] ?? ''}'),
      );
    } catch (_) {
      if (mounted && version == request) {
        setState(
          () => error =
              'Không tải được ký hiệu. Văn bản của bạn vẫn được giữ nguyên.',
        );
      }
    } finally {
      if (mounted && version == request) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = segments?.where((s) => s['type'] != 'punctuation').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: loading || widget.text.trim().isEmpty ? null : load,
          icon: const Icon(Icons.sign_language_outlined),
          label: Text(loading ? 'Đang tìm ký hiệu…' : 'Xem ký hiệu'),
        ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
        if (items != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Ký hiệu theo từ/cụm từ trong văn bản. Chưa phải bản dịch ngữ pháp ngôn ngữ ký hiệu.',
            ),
          ),
          if (items.isEmpty) const Text('Không có từ để tra ký hiệu.'),
          if (items.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => SignVideoDialog(
                  items: playbackItems(items),
                  initialIndex: 0,
                  playSequence: true,
                ),
              ),
              icon: const Icon(Icons.playlist_play),
              label: const Text('Xem lần lượt'),
            ),
          for (var i = 0; i < items.length; i++) _card(items[i], i, items),
        ],
      ],
    );
  }

  Widget _card(
    Map<String, dynamic> item,
    int index,
    List<Map<String, dynamic>> items,
  ) {
    final spelling = item['type'] == 'fingerspelling';
    final letters = (item['letters'] as List? ?? [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    final found = item['type'] == 'sign' || spelling;
    final images =
        (spelling
                ? letters
                      .map(
                        (letter) =>
                            letter['thumbnailUrl'] ??
                            (letter['imageUrls'] as List? ?? []).firstOrNull,
                      )
                      .whereType<String>()
                      .toList()
                : item['imageUrls'] as List? ?? [])
            .whereType<String>()
            .toList();
    final thumbnail = item['thumbnailUrl'] as String?;
    final video = item['videoUrl'] as String?;
    final pictures = images.isNotEmpty ? images : [?thumbnail];
    final attribution = spelling
        ? letters
              .map((letter) => letter['attribution'])
              .whereType<String>()
              .toSet()
              .join('\n\n')
        : item['attribution'] as String?;
    final message = switch (item['type']) {
      'ambiguous' =>
        'Có nhiều mẫu cùng tên; cần duyệt biến thể trước khi hiển thị.',
      'missing_media' => 'Mục từ chưa có ảnh/video dùng được.',
      _ => 'Chưa có ký hiệu đã xuất bản cho đoạn này.',
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${index + 1}. ${item['text']}',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            if (!found)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message),
              ),
            if (spelling) ...[
              const Text(
                'Đánh vần thay thế',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Wrap(
                spacing: 6,
                children: [
                  for (final letter in letters)
                    Chip(
                      label: Text(
                        '${letter['text']} (chữ ${'${letter['word']}'.toUpperCase()})',
                      ),
                    ),
                ],
              ),
              if (item['hasTone'] == true)
                const Text(
                  'Ảnh thể hiện chữ cái cơ bản; dấu thanh được giữ trong văn bản.',
                ),
            ],
            if (found && pictures.isNotEmpty) ...[
              SignReferenceImages(
                key: ValueKey(pictures.join('|')),
                urls: pictures,
                word: spelling ? 'Đánh vần ${item['text']}' : '${item['word']}',
                initialIndex: thumbnail != null && pictures.contains(thumbnail)
                    ? pictures.indexOf(thumbnail)
                    : 0,
              ),
              if (images.isEmpty)
                const Text('Ảnh xem trước; xem video để theo dõi động tác.'),
            ],
            if (found &&
                (video != null ||
                    spelling &&
                        letters.any((letter) => letter['videoUrl'] != null)))
              TextButton.icon(
                icon: const Icon(Icons.play_circle_outline),
                label: Text(spelling ? 'Xem đánh vần' : 'Xem động tác'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => SignVideoDialog(
                    items: spelling
                        ? playbackItems([item])
                        : playbackItems(items),
                    initialIndex: spelling
                        ? 0
                        : playbackItems(items).indexOf(item),
                    playSequence: spelling,
                  ),
                ),
              ),
            if (found && attribution != null && attribution.isNotEmpty)
              ExpansionTile(
                title: const Text('Nguồn và giấy phép'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      attribution,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class SignReferenceImages extends StatefulWidget {
  const SignReferenceImages({
    super.key,
    required this.urls,
    required this.word,
    this.initialIndex = 0,
  });
  final List<String> urls;
  final String word;
  final int initialIndex;
  @override
  State<SignReferenceImages> createState() => _SignReferenceImagesState();
}

class _SignReferenceImagesState extends State<SignReferenceImages> {
  late int index;
  late final PageController pages;
  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
    pages = PageController(initialPage: index);
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 240,
        child: PageView.builder(
          controller: pages,
          itemCount: widget.urls.length,
          onPageChanged: (value) => setState(() => index = value),
          itemBuilder: (_, i) => SignPhoto(
            widget.urls[i],
            word: '${widget.word}, ảnh ${i + 1}',
            height: 240,
            fit: BoxFit.contain,
          ),
        ),
      ),
      if (widget.urls.length > 1)
        Text(
          'Ảnh ${index + 1}/${widget.urls.length} · Vuốt để xem thứ tự động tác',
        ),
    ],
  );
}

class SignVideoDialog extends StatefulWidget {
  const SignVideoDialog({
    super.key,
    required this.items,
    required this.initialIndex,
    this.playSequence = false,
    this.videoLoader = openSignVideo,
    this.prefetch = prefetchSignVideo,
  });
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final bool playSequence;
  final Future<VideoSource> Function(String) videoLoader;
  final Future<void> Function(String) prefetch;
  @override
  State<SignVideoDialog> createState() => _SignVideoDialogState();
}

class _SignPlayback {
  _SignPlayback(this.source) : player = source.createController();
  final VideoSource source;
  final VideoPlayerController player;
  Future<void>? _disposing;
  Future<void> dispose() => _disposing ??= _release();
  Future<void> _release() async {
    try {
      await player.dispose();
    } finally {
      source.dispose();
    }
  }
}

class _SignVideoDialogState extends State<SignVideoDialog>
    with WidgetsBindingObserver {
  _SignPlayback? _playback;
  VideoPlayerController? get controller => _playback?.player;
  late final _prefetch = SignVideoPrefetch(load: widget.prefetch);
  late int index;
  int generation = 0;
  bool advancing = false;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    index = widget.initialIndex;
    open();
  }

  Future<void> open() async {
    final version = ++generation;
    final previous = _playback;
    _playback = null;
    await previous?.dispose();
    if (!mounted || version != generation) return;
    final url = widget.items[index]['videoUrl'] as String?;
    if (widget.items[index]['type'] != 'sign' || url == null) {
      _prefetch.warm(const []);
      setState(() {
        loading = false;
        error = 'Chưa có video cho đoạn này. Bấm tiếp để xem đoạn sau.';
      });
      return;
    }
    _prefetch.warm(
      widget.items
          .skip(index + 1)
          .take(2)
          .where((item) => item['type'] == 'sign')
          .map((item) => '${item['videoUrl'] ?? ''}'),
    );
    var accepting = true;
    _SignPlayback? playback;
    try {
      final resource = await widget
          .videoLoader(url)
          .then((resource) {
            if (!accepting || !mounted || version != generation) {
              resource.dispose();
              return null;
            }
            return resource;
          })
          .timeout(const Duration(seconds: 20));
      if (resource == null) return;
      playback = _SignPlayback(resource);
      _playback = playback;
      final player = playback.player;
      await player.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || version != generation) return;
      await player.setVolume(0);
      await player.setLooping(false);
      player.addListener(() {
        if (mounted &&
            version == generation &&
            player.value.hasError &&
            error == null) {
          setState(() {
            loading = false;
            error = 'Không phát được video. Bạn có thể thử lại.';
          });
          return;
        }
        if (mounted &&
            version == generation &&
            widget.playSequence &&
            !advancing &&
            player.value.isCompleted &&
            index < widget.items.length - 1) {
          advancing = true;
          scheduleMicrotask(() {
            if (mounted && version == generation) move(1);
          });
        }
      });
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
          WidgetsBinding.instance.lifecycleState == null) {
        await player.play();
      }
      if (mounted && version == generation) {
        setState(() {
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      accepting = false;
      await playback?.dispose();
      if (mounted && version == generation) {
        _playback = null;
        setState(() {
          loading = false;
          error = 'Không phát được video. Bạn có thể thử lại.';
        });
      }
    }
  }

  void move(int delta) {
    if (index + delta < 0 || index + delta >= widget.items.length) return;
    setState(() {
      index += delta;
      advancing = false;
      loading = true;
      error = null;
    });
    open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) controller?.pause();
  }

  @override
  void dispose() {
    generation++;
    _prefetch.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_playback?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      '${index + 1}/${widget.items.length}: ${widget.items[index]['text']}',
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.items[index]['type'] == 'sign')
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .35,
              child:
                  controller?.value.isInitialized == true &&
                      !loading &&
                      error == null
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: controller!.value.aspectRatio,
                        child: SignVideoSurface(controller!),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        SignPhoto(
                          widget.items[index]['thumbnailUrl'] as String? ??
                              (widget.items[index]['imageUrls'] as List?)
                                  ?.whereType<String>()
                                  .firstOrNull,
                          word: '${widget.items[index]['text']}',
                          height: MediaQuery.sizeOf(context).height * .35,
                        ),
                        if (loading)
                          const Align(
                            alignment: Alignment.bottomCenter,
                            child: Card(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Đang tải video…'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!),
            ),
          if (!loading && error == null && controller != null) ...[
            VideoProgressIndicator(controller!, allowScrubbing: true),
            Wrap(
              children: [
                TextButton(
                  onPressed: () => controller!.play(),
                  child: const Text('Phát'),
                ),
                TextButton(
                  onPressed: () => controller!.pause(),
                  child: const Text('Dừng'),
                ),
                TextButton(
                  onPressed: () async {
                    await controller!.seekTo(Duration.zero);
                    await controller!.play();
                  },
                  child: const Text('Phát lại'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: index > 0 ? () => move(-1) : null,
        child: const Text('Trước'),
      ),
      TextButton(
        onPressed: index < widget.items.length - 1 ? () => move(1) : null,
        child: const Text('Tiếp'),
      ),
      if (error != null)
        TextButton(
          onPressed: () {
            setState(() {
              loading = true;
              error = null;
            });
            open();
          },
          child: const Text('Thử lại'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Đóng'),
      ),
    ],
  );
}
