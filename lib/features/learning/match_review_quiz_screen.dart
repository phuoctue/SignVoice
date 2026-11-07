import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation.dart';
import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../services/media/managed_media.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';
import 'quiz_game_style.dart';
import 'quiz_game_layout.dart';
import 'recall_review_quiz_screen.dart' as recall;
import 'review_quiz_screen.dart' as camera;
import 'video_review_quiz_screen.dart' as choice;

/// Resolve saved drafts by their actual format, including older quiz links.
class ReviewQuizEntryScreen extends StatefulWidget {
  const ReviewQuizEntryScreen({super.key, required this.quizId});
  final String quizId;
  @override
  State<ReviewQuizEntryScreen> createState() => _ReviewQuizEntryScreenState();
}

class _ReviewQuizEntryScreenState extends State<ReviewQuizEntryScreen> {
  LearningRecord? quiz;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final value = await context.read<LearningService>().quiz(widget.quizId);
      if (mounted) setState(() => quiz = value);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa mở được bài ôn tập.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (quiz != null) {
      return switch (quiz!['kind']) {
        'VIDEO_MATCH' => MatchReviewQuizScreen(
          quizId: widget.quizId,
          initialQuiz: quiz,
        ),
        'VIDEO_CHOICE' => choice.ReviewQuizScreen(quizId: widget.quizId),
        'CAMERA' => camera.ReviewQuizScreen(quizId: widget.quizId),
        _ => recall.ReviewQuizScreen(quizId: widget.quizId, initialQuiz: quiz),
      };
    }
    return AppPage(
      title: 'Ôn tập',
      child: Column(
        children: [
          if (error == null)
            const LinearProgressIndicator()
          else ...[
            Notice(error!),
            TextButton(onPressed: load, child: const Text('Thử lại')),
          ],
        ],
      ),
    );
  }
}

class MatchReviewQuizScreen extends StatefulWidget {
  const MatchReviewQuizScreen({
    super.key,
    required this.quizId,
    this.initialQuiz,
  });
  final String quizId;
  final LearningRecord? initialQuiz;
  @override
  State<MatchReviewQuizScreen> createState() => _MatchReviewQuizScreenState();
}

class _MatchReviewQuizScreenState extends State<MatchReviewQuizScreen> {
  LearningRecord? quiz;
  String? error, selected, message, playing;
  LearningRecord? advice;
  String? adviceError;
  bool adviceBusy = false;
  bool busy = false, loading = true;
  int round = 0;
  bool roundDialogOpen = false;
  final celebratedRounds = <int>{};
  final scroll = ScrollController();
  ({String entry, String option, String request})? pending;
  AppRouteExitController? exitGuard;
  LearningService get service => context.read<LearningService>();
  List<LearningRecord> get questions => (quiz?['questions'] as List? ?? [])
      .map((q) => LearningRecord.from(q as Map))
      .toList();
  List<LearningRecord> get options => (quiz?['matchOptions'] as List? ?? [])
      .map((q) => LearningRecord.from(q as Map))
      .toList();
  bool get completed => quiz?['status'] == 'COMPLETED';
  bool done(LearningRecord q) => (q['response'] as Map?)?['matched'] == true;
  int get solved => questions.where(done).length;
  int get roundCount =>
      options.fold<int>(
        0,
        (value, o) => value > (o['round'] as num).toInt()
            ? value
            : (o['round'] as num).toInt(),
      ) +
      1;
  List<LearningRecord> get current =>
      questions.where((q) => q['round'] == round).toList();
  bool get roundDone => current.isNotEmpty && current.every(done);
  bool get blocked => busy || pending != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load(initial: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    exitGuard = AppRouteExitScope.maybeOf(context);
    exitGuard?.handler = () async => !busy;
  }

  @override
  void dispose() {
    exitGuard?.handler = null;
    scroll.dispose();
    super.dispose();
  }

  void apply(LearningRecord value) {
    quiz = value;
    primeImagePreviews(questions);
  }

  Future<void> load({bool initial = false}) async {
    if (busy) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = initial && widget.initialQuiz != null
          ? widget.initialQuiz!
          : await service.quiz(widget.quizId);
      if (!mounted) return;
      setState(() {
        apply(value);
        pending = null;
        selected = null;
        round =
            questions
                .where((q) => !done(q))
                .map((q) => (q['round'] as num).toInt())
                .firstOrNull ??
            0;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa tải được lượt chơi. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pair(String entry, String option) async {
    if (blocked) return;
    pending = (
      entry: entry,
      option: option,
      request: service.newMatchRequestId(),
    );
    await sendPair();
  }

  Future<void> sendPair() async {
    final operation = pending;
    if (busy || operation == null) return;
    setState(() {
      busy = true;
      error = null;
      playing = null;
    });
    try {
      final value = await service.matchQuizPair(
        widget.quizId,
        operation.entry,
        operation.option,
        operation.request,
      );
      if (!mounted) return;
      setState(() {
        apply(value);
        final q = questions.firstWhere((q) => q['entryId'] == operation.entry);
        message = done(q)
            ? 'Ghép đúng! Bạn có thể xem lại mẫu trước khi tiếp tục.'
            : 'Chưa khớp. Hãy xem lại mẫu rồi thử thẻ khác.';
        selected = null;
        pending = null;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException ? e.message : 'Chưa xác nhận được lượt ghép. Hãy gửi lại hoặc tải trạng thái đã lưu.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && pending == null && roundDone) await celebrateRound();
  }

  Future<void> hint(LearningRecord q) async {
    if (blocked) return;
    setState(() {
      busy = true;
      error = null;
      playing = null;
    });
    try {
      final value = await service.matchQuizHint(
        widget.quizId,
        '${q['entryId']}',
      );
      if (mounted) {
        setState(() {
          apply(value);
          message = 'Gợi ý đã mở. Từ này sẽ được ghi nhận là có hỗ trợ.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa mở được gợi ý. Hãy thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> finish() async {
    if (blocked || solved != questions.length) return;
    setState(() {
      busy = true;
      error = null;
      playing = null;
    });
    try {
      final value = await service.submitQuiz(widget.quizId);
      if (mounted) setState(() => apply(value));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException ? e.message : 'Chưa lưu được kết quả. Các cặp đã ghép vẫn được giữ lại; hãy thử nộp lại.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget option(LearningRecord o) {
    final id = '${o['value']}', label = '${o['label']}';
    final used = questions.any(
      (q) => done(q) && (q['response'] as Map)['selectedOptionId'] == id,
    );
    final p = QuizGamePalette(context), active = selected == id;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        gradient: used
            ? null
            : LinearGradient(
                colors: active ? [p.soft, p.soft] : [p.soft, p.backgroundEnd],
              ),
        color: used ? p.successSurface : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: active
            ? [
                BoxShadow(
                  color: p.primary.withValues(alpha: .16),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: OutlinedButton(
        key: ValueKey('match-option-$id'),
        onPressed: blocked || used
            ? null
            : () => setState(() => selected = active ? null : id),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(140, 64),
          maximumSize: const Size(300, double.infinity),
          foregroundColor: p.primary,
          disabledForegroundColor: used ? p.success : p.muted,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          side: BorderSide(
            color: used
                ? p.success.withValues(alpha: .3)
                : active
                ? p.primary
                : p.primary.withValues(alpha: .2),
            width: active ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              used ? Icons.check_circle_rounded : Icons.drag_indicator_rounded,
              size: 20,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (blocked || used) return card;
    return Draggable<String>(
      data: id,
      feedback: Material(
        color: Colors.transparent,
        child: QuizGlassPanel(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'PlusJakartaSans',
              color: p.primary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .35, child: card),
      child: card,
    );
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
          () => adviceError = e is ApiException
              ? e.message
              : 'Chưa tải được gợi ý. Bạn vẫn có thể xem lại kết quả đã lưu.',
        );
      }
    } finally {
      if (mounted) setState(() => adviceBusy = false);
    }
  }

  Widget sample(LearningRecord q, int position) {
    final id = '${q['entryId']}',
        matched = done(q),
        response = q['response'] as Map?;
    final matchedOption = options
        .where((o) => o['value'] == response?['selectedOptionId'])
        .firstOrNull;
    final hintedOption = options
        .where((o) => o['value'] == q['hintOptionId'])
        .firstOrNull;
    final selectedOption = options
        .where((o) => o['value'] == selected)
        .firstOrNull;
    final p = QuizGamePalette(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => !blocked && !matched,
      onAcceptWithDetails: (details) => pair(id, details.data),
      builder: (context, candidates, rejected) => QuizGlassPanel(
        padding: const EdgeInsets.all(20),
        highlight: candidates.isNotEmpty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: matched ? p.successSurface : p.soft,
                    border: Border.all(
                      color: matched ? p.success.withValues(alpha: .2) : p.line,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        matched
                            ? Icons.check_circle_rounded
                            : Icons.videocam_outlined,
                        size: 16,
                        color: matched ? p.success : p.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Mẫu ${position + 1}',
                        style: TextStyle(
                          color: matched ? p.success : p.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (!matched)
                  IconButton(
                    tooltip: 'Gợi ý mẫu ${position + 1}',
                    onPressed: blocked ? null : () => hint(q),
                    icon: Icon(Icons.lightbulb_outline_rounded, color: p.amber),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Listener(
              onPointerDown: blocked
                  ? null
                  : (_) => setState(() => playing = id),
              child: LayoutBuilder(
                builder: (context, size) => LearningWordContent(
                  {...q, 'word': 'Mẫu ký hiệu ${position + 1}'},
                  key: ValueKey('match-media-$id'),
                  showMeaning: false,
                  hideQuizLabels: true,
                  quizControls: true,
                  gameStyle: true,
                  previewHeight: ((size.maxWidth) * 9 / 16).clamp(160.0, 260.0),
                  showFrames: true,
                  pauseVideo: playing != id,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: matched
                  ? 'Mẫu ${position + 1} đã ghép đúng: ${matchedOption?['label']}'
                  : 'Ghép thẻ đã chọn vào mẫu ${position + 1}',
              button: !matched,
              child: CustomPaint(
                foregroundPainter: matched
                    ? null
                    : QuizDashedBorder(
                        candidates.isNotEmpty || selected != null
                            ? p.primary
                            : p.primary.withValues(alpha: .3),
                      ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: matched
                        ? p.successSurface
                        : p.soft.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(16),
                    border: matched
                        ? Border.all(color: p.success.withValues(alpha: .3))
                        : null,
                  ),
                  child: TextButton(
                    key: ValueKey('match-target-$id'),
                    onPressed: blocked || matched || selected == null
                        ? null
                        : () => pair(id, selected!),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(double.infinity, 80),
                      padding: const EdgeInsets.all(16),
                      foregroundColor: p.primary,
                      disabledForegroundColor: matched ? p.success : p.muted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          matched
                              ? Icons.check_circle_rounded
                              : Icons.move_to_inbox_outlined,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            matched
                                ? '${matchedOption?['label']}'
                                : selectedOption == null
                                ? 'Thả thẻ vào đây'
                                : 'Ghép “${selectedOption['label']}”',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: matched ? 16 : 14,
                              fontWeight: matched
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (hintedOption != null && !matched)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Gợi ý: ${hintedOption['label']}',
                  style: TextStyle(color: p.amber, fontWeight: FontWeight.w700),
                ),
              ),
            if (!matched && (response?['attempts'] as num? ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Xem lại mẫu và thử thẻ khác.',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> advance() async {
    if (blocked) return;
    if (solved == questions.length) {
      await finish();
      return;
    }
    setState(() {
      round++;
      selected = null;
      message = null;
      playing = null;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> celebrateRound() async {
    if (roundDialogOpen ||
        celebratedRounds.contains(round) ||
        !roundDone ||
        completed) {
      return;
    }
    celebratedRounds.add(round);
    setState(() => roundDialogOpen = true);
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: QuizGamePalette(context).theme(Theme.of(context)),
        child: QuizRoundDialog(
          lastRound: solved == questions.length,
          onContinue: () => Navigator.of(dialogContext).pop(true),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => roundDialogOpen = false);
    if (proceed == true) await advance();
  }

  Widget results() {
    final result = LearningRecord.from(quiz!['result'] as Map);
    final summary = result['summary'] as Map? ?? {};
    final items = (result['items'] as List? ?? []).map(
      (v) => LearningRecord.from(v as Map),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuizResultHero(
          points: result['gamePoints'] ?? 0,
          firstTry: summary['firstTry'] ?? 0,
          practiced: summary['practiced'] ?? 0,
        ),
        const SizedBox(height: 20),
        Notice('${result['feedback']}'),
        const SizedBox(height: 16),
        QuizGlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Heading('Gợi ý ôn tập', size: 19),
              const SizedBox(height: 8),
              if (advice != null) ...[
                Text(
                  advice!['source'] == 'lm-studio'
                      ? 'Gợi ý từ trợ lý AI'
                      : 'Gợi ý ôn tập cơ bản',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text('${advice!['advice']}'),
              ],
              if (adviceError != null) Notice(adviceError!),
              if (advice == null)
                AppButton(
                  adviceBusy ? 'Đang chuẩn bị gợi ý' : 'Nhận gợi ý ôn tập',
                  busy: adviceBusy,
                  onPressed: adviceBusy ? null : getAdvice,
                  icon: Icons.auto_awesome,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: QuizGlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['word']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text('${item['feedback']}'),
                  if (item['applied'] == false)
                    const Text('Tiến độ mới hơn được giữ nguyên.'),
                  TextButton.icon(
                    onPressed: () {
                      final media = questions
                          .where((q) => q['entryId'] == item['entryId'])
                          .firstOrNull;
                      if (media != null) {
                        showLearningWord(context, {...media, ...item});
                      }
                    },
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Xem lại ký hiệu'),
                  ),
                ],
              ),
            ),
          ),
        AppButton(
          quiz!['collectionId'] != null ? 'Về bộ từ' : 'Về chủ đề',
          icon: Icons.arrow_back,
          onPressed: () => replaceAppRoute(
            context,
            quiz!['collectionId'] != null
                ? '/collections/${quiz!['collectionId']}'
                : '/learn/topic/${quiz!['topicId']}?study=1',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = !loading && quiz != null;
    final playable =
        ready && quiz!['kind'] == 'VIDEO_MATCH' && quiz!['status'] == 'DRAFT';
    final firstTry = questions.where((q) {
      final r = q['response'] as Map?;
      return r?['matched'] == true &&
          r?['firstCorrect'] == true &&
          r?['usedHint'] != true;
    }).length;
    final p = QuizGamePalette(context);
    return PopScope<Object?>(
      canPop: !busy,
      child: QuizGameScaffold(
        controller: scroll,
        onBack: busy ? null : () => backOrHome(context),
        onReload: busy || loading ? null : load,
        solved: solved,
        total: questions.length,
        firstTry: firstTry,
        completed: completed,
        dock: !playable
            ? null
            : QuizMeaningDock(
                children: options
                    .where((o) => o['round'] == round)
                    .map(option)
                    .toList(),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (loading || busy) const LinearProgressIndicator(),
            if (error != null) ...[
              Notice(error!),
              if (pending != null)
                TextButton(
                  onPressed: busy ? null : sendPair,
                  child: const Text('Gửi lại lượt ghép'),
                ),
              if (quiz == null)
                TextButton(onPressed: load, child: const Text('Thử lại')),
              const SizedBox(height: 16),
            ],
            if (ready && completed)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: results(),
                ),
              )
            else if (ready && quiz!['kind'] != 'VIDEO_MATCH')
              const Notice(
                'Lượt này dùng kiểu ôn tập khác. Hãy quay lại và mở lại lượt ôn.',
              )
            else if (ready && !playable)
              const Notice(
                'Lượt này không còn khả dụng do nội dung đã thay đổi. Hãy quay lại chủ đề hoặc bộ từ để mở lượt ôn mới.',
              )
            else if (ready) ...[
              QuizInstructionBanner(
                round: round,
                roundCount: roundCount,
                solved: solved,
                total: questions.length,
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: p.surface.withValues(alpha: .94),
                        border: Border.all(color: p.line),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            message!.startsWith('Chưa')
                                ? Icons.info_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            color: message!.startsWith('Chưa')
                                ? p.amber
                                : p.success,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message!,
                              style: TextStyle(
                                color: p.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              LayoutBuilder(
                builder: (context, size) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  final available = size.maxWidth >= 1180
                      ? 4
                      : size.maxWidth >= 900
                      ? 3
                      : size.maxWidth >= 640
                      ? 2
                      : 1;
                  final columns = current.length.clamp(
                    1,
                    scale >= 1.5 ? 1 : available,
                  );
                  return Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    children: [
                      for (final (index, q) in current.indexed)
                        SizedBox(
                          width: (size.maxWidth - (columns - 1) * 24) / columns,
                          child: sample(q, index),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              if (roundDone && !roundDialogOpen)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: QuizGradientButton(
                      solved == questions.length
                          ? 'Hoàn tất và lưu kết quả'
                          : 'Vòng tiếp theo',
                      busy: busy,
                      onPressed: blocked ? null : advance,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
