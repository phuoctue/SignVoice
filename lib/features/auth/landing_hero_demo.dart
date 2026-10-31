import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../services/admin/admin_workspace_service.dart';
import '../../services/sign_ai/speech_output.dart';
import '../../widgets/public_sign_preview.dart';
import 'landing_motion.dart';

/// Real public samples, with explicit text input/output and opt-in speech.
class LandingHeroDemo extends StatefulWidget {
  const LandingHeroDemo({
    super.key,
    required this.words,
    required this.loading,
    this.scroll,
    this.portalSignal,
  });
  final List<AdminRecord> words;
  final bool loading;
  final ScrollController? scroll;
  final ValueListenable<int>? portalSignal;
  @override
  State<LandingHeroDemo> createState() => _LandingHeroDemoState();
}

class _LandingHeroDemoState extends State<LandingHeroDemo> {
  int mode = 0, selected = 0, _request = 0;
  final input = TextEditingController();
  AdminRecord? found;
  bool searching = false, speaking = false, attemptedLookup = false;
  String? message;
  SpeechOutput? speech;
  AdminRecord? get sample => attemptedLookup
      ? found
      : (widget.words.isEmpty
            ? null
            : widget.words[selected.clamp(0, widget.words.length - 1)]);

  void choose(int index) {
    speech?.stop();
    setState(() {
      selected = index;
      attemptedLookup = false;
      found = null;
      message = null;
      speaking = false;
      input.text = '${widget.words[index]['word']}';
    });
  }

  Future<void> lookup() async {
    final query = input.text.trim(),
        service = context.read<AdminWorkspaceService?>();
    if (query.isEmpty || service == null) return;
    final request = ++_request;
    setState(() {
      searching = true;
      message = null;
    });
    try {
      final page = await service.published(search: query, sort: '');
      if (!mounted || request != _request) return;
      final matches = page.items
          .where(
            (word) => '${word['word']}'.toLowerCase() == query.toLowerCase(),
          )
          .toList();
      setState(() {
        attemptedLookup = true;
        found = matches.isEmpty ? null : matches.first;
        message = matches.isEmpty
            ? 'Chưa có mẫu khớp từ này. Thử tra cứu thư viện bên dưới.'
            : null;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          attemptedLookup = true;
          found = null;
          message = 'Chưa tải được mẫu. Hãy thử lại.';
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => searching = false);
    }
  }

  Future<void> speak() async {
    if (sample == null || speaking) return;
    setState(() {
      speaking = true;
      message = null;
    });
    try {
      speech ??= SpeechOutput();
      await speech!.speak('${sample!['word']}', speed: 1, pitch: 1);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Thiết bị chưa có giọng tiếng Việt. Bạn vẫn có thể xem lời nói bên dưới.',
        );
      }
    } finally {
      if (mounted) setState(() => speaking = false);
    }
  }

  @override
  void dispose() {
    _request++;
    input.dispose();
    speech?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme,
        reduce = MediaQuery.disableAnimationsOf(context);
    final word = sample, name = '${word?['word'] ?? ''}';
    final empty = word == null && !widget.loading && !searching;
    if (input.text.isEmpty && name.isNotEmpty) input.text = name;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: landingGlass(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('demo-mode-sign'),
                label: const Text('Ký hiệu → Giọng nói'),
                selected: mode == 0,
                onSelected: (_) => setState(() => mode = 0),
              ),
              ChoiceChip(
                key: const ValueKey('demo-mode-speech'),
                label: const Text('Văn bản → Ký hiệu'),
                selected: mode == 1,
                onSelected: (_) => setState(() => mode = 1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 260),
            child: mode == 0
                ? Align(
                    key: const ValueKey('sign-input'),
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Mẫu ký hiệu: ${name.isEmpty ? 'Lời chào' : name}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                : TextField(
                    key: const ValueKey('hero-text-input'),
                    controller: input,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Văn bản đầu vào',
                      suffixIcon: IconButton(
                        tooltip: 'Tìm mẫu ký hiệu',
                        onPressed: searching ? null : lookup,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                    onSubmitted: (_) => lookup(),
                  ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: empty
                ? Container(
                    height: 270,
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    color: scheme.surfaceContainerHighest,
                    child: Text(
                      attemptedLookup
                          ? 'Chưa có mẫu khớp với nội dung vừa nhập.'
                          : 'Chưa tải được mẫu lời chào. Bạn vẫn có thể khám phá từ điển bên dưới.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : AnimatedSwitcher(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    child: PublicSignPreview(
                      key: ValueKey('$mode-$name'),
                      word: word ?? {},
                      height: 270,
                      autoplay: true,
                      loading: widget.loading || searching,
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode == 0 ? 'Lời nói đầu ra' : 'Ký hiệu tương ứng',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name.isEmpty ? 'Chọn một mẫu để bắt đầu' : name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (mode == 0)
                  TextButton.icon(
                    onPressed: word == null || speaking ? null : speak,
                    icon: Icon(
                      speaking ? Icons.volume_up : Icons.volume_up_outlined,
                    ),
                    label: Text(speaking ? 'Đang phát…' : 'Nghe lời chào'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < widget.words.take(3).length; i++)
                ActionChip(
                  key: ValueKey('demo-sample-$i'),
                  avatar: Icon(
                    i == selected && found == null
                        ? Icons.check_circle_outline
                        : Icons.touch_app_outlined,
                    size: 18,
                  ),
                  label: Text('${widget.words[i]['word']}'),
                  onPressed: () => choose(i),
                ),
            ],
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(message!, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 14),
          Text(
            'Xem mẫu từ thư viện · Video tắt tiếng. Chỉ phát giọng nói khi bạn bấm nghe. Camera và microphone chưa được bật.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
