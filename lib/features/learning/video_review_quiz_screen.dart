import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation.dart';
import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../services/media/sign_video_prefetch.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';

/// Video comprehension quiz. Camera recognition remains a separate feature.
class ReviewQuizScreen extends StatefulWidget {
  const ReviewQuizScreen({super.key, required this.quizId});
  final String quizId;
  @override
  State<ReviewQuizScreen> createState() => _ReviewQuizScreenState();
}

class _ReviewQuizScreenState extends State<ReviewQuizScreen> {
  LearningRecord? quiz, advice;
  List<String> answers = [], saved = [];
  int index = 0;
  bool loading = true, busy = false, adviceBusy = false;
  String? error, adviceError;
  final prefetch = SignVideoPrefetch();
  final scroll = ScrollController();
  LearningService get service => context.read<LearningService>();
  List<LearningRecord> get questions => (quiz?['questions'] as List? ?? [])
      .map((value) => LearningRecord.from(value as Map))
      .toList();
  bool get dirty => answers.join('|') != saved.join('|');
  bool get completed => quiz?['status'] == 'COMPLETED';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    prefetch.dispose();
    scroll.dispose();
    super.dispose();
  }

  String message(Object exception, String fallback) =>
      exception is ApiException ? exception.message : fallback;

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await service.quiz(widget.quizId);
      if (!mounted) return;
      quiz = value;
      final restored = value['answers'] as List? ?? [];
      answers = List.generate(
        questions.length,
        (i) => i < restored.length ? '${restored[i]}' : '',
      );
      saved = [...answers];
      final unanswered = answers.indexOf('');
      index = unanswered < 0 ? 0 : unanswered;
      warm();
    } catch (e) {
      if (mounted) error = message(e, 'Chưa tải được bài ôn tập. Hãy thử lại.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void warm() {
    final list = questions;
    prefetch.warm(
      index + 1 < list.length ? ['${list[index + 1]['videoUrl'] ?? ''}'] : [],
    );
  }

  Future<void> persist() async {
    if (!dirty) return;
    final snapshot = [...answers];
    await service.saveQuizAnswers(widget.quizId, snapshot);
    if (mounted) saved = snapshot;
  }

  void top() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) scroll.jumpTo(0);
  });

  Future<void> move(int next) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await persist();
      if (!mounted) return;
      setState(() => index = next);
      warm();
      top();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = message(
            e,
            'Chưa lưu được lựa chọn. Đáp án vẫn được giữ trên màn hình; hãy thử lại.',
          ),
        );
        top();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    final missing = answers.indexOf('');
    if (missing >= 0) {
      setState(() {
        index = missing;
        error = 'Hãy chọn đáp án cho câu ${missing + 1} trước khi nộp.';
      });
      top();
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nộp bài ôn tập?'),
        content: Text(
          'Bạn đã chọn ${answers.length}/${answers.length} câu. Sau khi nộp, bạn có thể xem đáp án và gợi ý ôn tập.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Xem lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nộp bài'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await persist();
      final result = await service.submitQuiz(widget.quizId);
      if (!mounted) return;
      setState(() => quiz = result);
      prefetch.warm([]);
      top();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = message(
            e,
            'Chưa nộp được bài. Lựa chọn được giữ lại; hãy thử nộp lại.',
          ),
        );
        top();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> leave() async {
    if (busy) return;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lưu lựa chọn trước khi thoát?'),
        content: const Text(
          'Bạn có lựa chọn chưa được lưu. Bài đã lưu có thể tiếp tục khi mở lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ở lại'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Thoát không lưu'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Lưu & thoát'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'save') {
      setState(() => busy = true);
      try {
        await persist();
      } catch (e) {
        if (mounted) {
          setState(() {
            busy = false;
            error = message(e, 'Chưa lưu được bài. Hãy thử lại.');
          });
          top();
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      saved = [...answers];
      busy = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) backOrHome(context);
  }

  Future<void> getAdvice() async {
    if (adviceBusy) return;
    setState(() {
      adviceBusy = true;
      adviceError = null;
    });
    try {
      final value = await service.quizAdvice(widget.quizId);
      if (mounted) setState(() => advice = value);
    } catch (e) {
      if (mounted) {
        setState(
          () => adviceError = message(
            e,
            'Chưa lấy được nhận xét AI. Điểm và kết quả của bạn đã được lưu.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => adviceBusy = false);
    }
  }

  Widget option(LearningRecord value, int position) {
    final selected = answers[index] == value['value'];
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy
                ? null
                : () => setState(() {
                    answers[index] = '${value['value']}';
                    error = null;
                  }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Text(
                    String.fromCharCode(65 + position),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '${value['label']}',
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget resultView() {
    final result = LearningRecord.from(quiz!['result'] as Map);
    final items = (result['items'] as List? ?? [])
        .map((v) => LearningRecord.from(v as Map))
        .toList();
    final correct = items.where((item) => item['score'] == 10).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading('Kết quả ôn tập', size: 24),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Heading('${result['score']} / 10 điểm', size: 28),
              const SizedBox(height: 8),
              BodyText('Đúng $correct/${items.length} câu'),
              const SizedBox(height: 8),
              const BodyText(
                'Điểm đánh giá ghi nhớ nghĩa ký hiệu, chưa đánh giá động tác thực hành.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Heading('Xem lại đáp án', size: 19),
        const SizedBox(height: 12),
        for (final (i, item) in items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item['score'] == 10
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        color: item['score'] == 10
                            ? const Color(0xFF15803D)
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Heading(
                          'Câu ${i + 1} · ${item['score'] == 10 ? 'Đúng' : 'Chưa đúng'}',
                          size: 17,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  BodyText(
                    'Bạn chọn: ${item['selectedAnswer'] ?? item['recognizedLabel'] ?? ''}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Đáp án: ${item['correctAnswer'] ?? item['word']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if ('${item['definition'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    BodyText('${item['definition']}'),
                  ],
                  if (item['applied'] == false) ...[
                    const SizedBox(height: 8),
                    const BodyText(
                      'Tiến độ đã thay đổi trong lúc làm bài; hệ thống giữ trạng thái mới nhất.',
                    ),
                  ],
                  if (i < questions.length)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Xem lại ký hiệu'),
                      children: [
                        LearningWordContent({
                          ...questions[i],
                          'word': item['word'],
                        }, showMeaning: false),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Heading('Nhận xét & gợi ý ôn tập', size: 19),
              const SizedBox(height: 8),
              if (advice == null && !adviceBusy)
                const BodyText(
                  'Xem nhận xét và kế hoạch ôn ngắn dựa trên bài vừa làm.',
                ),
              if (adviceBusy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                const BodyText(
                  'AI đang viết nhận xét. Điểm và đáp án đã được lưu; bạn có thể xem lại trong lúc chờ.',
                ),
              ],
              if (advice != null) ...[
                Text(
                  advice!['source'] == 'lm-studio'
                      ? 'Gợi ý từ LM Studio'
                      : 'Gợi ý ôn tập cơ bản',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SelectableText('${advice!['advice']}'),
              ],
              if (adviceError != null) ...[
                const SizedBox(height: 8),
                Notice(adviceError!),
              ],
              if (advice == null) ...[
                const SizedBox(height: 12),
                AppButton(
                  adviceBusy ? 'Đang viết nhận xét' : 'Nhận gợi ý ôn tập',
                  icon: Icons.auto_awesome,
                  busy: adviceBusy,
                  onPressed: adviceBusy ? null : getAdvice,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = questions;
    final ready = !loading && quiz != null;
    final supported = quiz?['kind'] == 'VIDEO_CHOICE';
    final question = list.isEmpty
        ? null
        : list[index.clamp(0, list.length - 1)];
    final options = (question?['options'] as List? ?? [])
        .map((v) => LearningRecord.from(v as Map))
        .toList();
    return PopScope<Object?>(
      canPop: !dirty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy && dirty) leave();
      },
      child: _QuizPage(
        title: 'Quiz ôn tập',
        onBack: busy
            ? null
            : () {
                if (dirty) {
                  leave();
                } else {
                  backOrHome(context);
                }
              },
        footer: ready
            ? (completed || !supported || question == null
                  ? AppButton(
                      'Về chủ đề',
                      icon: Icons.arrow_back,
                      onPressed: () => replaceAppRoute(
                        context,
                        '/learn/topic/${quiz!['topicId']}?study=1',
                      ),
                    )
                  : Row(
                      children: [
                        IconButton(
                          tooltip: 'Câu trước',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: busy || index == 0
                              ? null
                              : () => move(index - 1),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppButton(
                            index == list.length - 1 ? 'Nộp bài' : 'Câu tiếp',
                            busy: busy,
                            icon: index == list.length - 1
                                ? Icons.check
                                : Icons.arrow_forward,
                            onPressed: busy || answers[index].isEmpty
                                ? null
                                : () {
                                    if (index == list.length - 1) {
                                      submit();
                                    } else {
                                      move(index + 1);
                                    }
                                  },
                          ),
                        ),
                      ],
                    ))
            : null,
        child: SingleChildScrollView(
          controller: scroll,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null) ...[
                Notice(error!),
                if (quiz == null)
                  TextButton(onPressed: load, child: const Text('Thử lại')),
                const SizedBox(height: 12),
              ],
              if (ready && completed && quiz!['result'] is Map)
                resultView()
              else if (ready && !supported)
                const Notice(
                  'Đây là bài ôn tập của phiên bản cũ. Hãy về chủ đề và bắt đầu quiz xem video mới.',
                )
              else if (ready && question == null)
                const Notice(
                  'Bài này chưa có câu hỏi. Hãy về chủ đề để tạo lại bài.',
                )
              else if (ready && question != null) ...[
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    Heading('Câu ${index + 1} / ${list.length}', size: 21),
                    Text(
                      'Đã chọn ${answers.where((v) => v.isNotEmpty).length}/${list.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: (index + 1) / list.length),
                const SizedBox(height: 18),
                const Heading('Ký hiệu này có nghĩa là gì?', size: 23),
                const SizedBox(height: 8),
                const BodyText(
                  'Xem video hoặc chuỗi ảnh, rồi chọn một đáp án.',
                ),
                const SizedBox(height: 14),
                LearningWordContent(
                  {...question, 'word': 'Ký hiệu câu ${index + 1}'},
                  key: ValueKey('quiz-media-${question['entryId']}'),
                  showMeaning: false,
                  hideQuizLabels: true,
                ),
                const SizedBox(height: 18),
                for (final (position, value) in options.indexed)
                  option(value, position),
                const SizedBox(height: 4),
                const BodyText(
                  'Lựa chọn được lưu khi chuyển câu hoặc nộp bài. Bạn có thể quay lại để đổi đáp án.',
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The quiz handles back navigation itself so an unsaved choice is never lost
/// through the shared page's immediate programmatic pop.
class _QuizPage extends StatelessWidget {
  const _QuizPage({
    required this.title,
    required this.onBack,
    required this.child,
    this.footer,
  });
  final String title;
  final VoidCallback? onBack;
  final Widget child;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      leading: IconButton(
        tooltip: 'Quay lại',
        onPressed: onBack,
        icon: const Icon(Icons.chevron_left),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: child,
      ),
    ),
    bottomNavigationBar: footer == null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: footer,
            ),
          ),
  );
}
