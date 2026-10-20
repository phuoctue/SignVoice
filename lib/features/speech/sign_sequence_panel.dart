import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';

typedef SequenceLoader = Future<Map<String, dynamic>> Function(String text);

Future<Map<String, dynamic>> loadSignSequence(String text) async {
  final response = await ApiClient.instance.post(
    '/sign-sequence',
    body: {'text': text},
    requiresAuth: false,
  );
  final data = Map<String, dynamic>.from(response['data'] as Map);
  data['segments'] = (data['segments'] as List).map((value) {
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
    return segment;
  }).toList();
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

  @override
  void didUpdateWidget(covariant SignSequencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
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
                  items: items,
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
    final found = item['type'] == 'sign';
    final images = (item['imageUrls'] as List? ?? [])
        .whereType<String>()
        .toList();
    final thumbnail = item['thumbnailUrl'] as String?;
    final video = item['videoUrl'] as String?;
    final pictures = images.isNotEmpty ? images : [?thumbnail];
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
            if (found && pictures.isNotEmpty) ...[
              _SignFrames(
                key: ValueKey(pictures.join('|')),
                urls: pictures,
                word: '${item['word']}',
                initialIndex: thumbnail != null && pictures.contains(thumbnail)
                    ? pictures.indexOf(thumbnail)
                    : 0,
              ),
              if (images.isEmpty)
                const Text('Ảnh xem trước; xem video để theo dõi động tác.'),
            ],
            if (found && video != null)
              TextButton.icon(
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Xem động tác'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      SignVideoDialog(items: items, initialIndex: index),
                ),
              ),
            if (found && item['attribution'] is String)
              ExpansionTile(
                title: const Text('Nguồn và giấy phép'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      item['attribution'] as String,
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

class _SignFrames extends StatefulWidget {
  const _SignFrames({
    super.key,
    required this.urls,
    required this.word,
    this.initialIndex = 0,
  });
  final List<String> urls;
  final String word;
  final int initialIndex;
  @override
  State<_SignFrames> createState() => _SignFramesState();
}

class _SignFramesState extends State<_SignFrames> {
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
          itemBuilder: (_, i) => Image.network(
            widget.urls[i],
            fit: BoxFit.contain,
            semanticLabel: 'Mẫu ${widget.word}, ảnh ${i + 1}',
            errorBuilder: (_, _, _) =>
                const Center(child: Text('Không tải được ảnh mẫu.')),
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
  });
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final bool playSequence;
  @override
  State<SignVideoDialog> createState() => _SignVideoDialogState();
}

class _SignVideoDialogState extends State<SignVideoDialog>
    with WidgetsBindingObserver {
  VideoPlayerController? controller;
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
    final previous = controller;
    controller = null;
    await previous?.dispose();
    if (!mounted || version != generation) return;
    final url = widget.items[index]['videoUrl'] as String?;
    if (widget.items[index]['type'] != 'sign' || url == null) {
      setState(() {
        loading = false;
        error = 'Chưa có video cho đoạn này. Bấm tiếp để xem đoạn sau.';
      });
      return;
    }
    final player = VideoPlayerController.networkUrl(Uri.parse(url));
    controller = player;
    try {
      await player.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || version != generation) return;
      await player.setVolume(0);
      await player.setLooping(false);
      player.addListener(() {
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
      await player.play();
      if (mounted && version == generation) {
        setState(() {
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && version == generation) {
        setState(() {
          loading = false;
          error = 'Không phát được video. Bạn có thể thử lại.';
        });
      }
    }
  }

  void move(int delta) {
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
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${index + 1}/${widget.items.length}: ${widget.items[index]['text']}',
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else if (error != null)
            Text(error!)
          else if (controller != null) ...[
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .35,
              child: Center(
                child: AspectRatio(
                  aspectRatio: controller!.value.aspectRatio,
                  child: VideoPlayer(controller!),
                ),
              ),
            ),
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
