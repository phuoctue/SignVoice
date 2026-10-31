import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation.dart';
import '../../services/api/api_exception.dart';
import '../../services/learning/learning_service.dart';
import '../../services/media/sign_video_prefetch.dart';
import '../../services/media/managed_media.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';
import 'quiz_practice_sheet.dart';

class ReviewQuizScreen extends StatefulWidget {
  const ReviewQuizScreen({
    super.key,
    required this.quizId,
    this.mirrorFactory = createQuizMirror,
  });
  final String quizId;
  final QuizMirror Function() mirrorFactory;
  @override
  State<ReviewQuizScreen> createState() => _ReviewQuizScreenState();
}

class _ReviewQuizScreenState extends State<ReviewQuizScreen> {
  LearningRecord? quiz, advice;
  List<String> answers = [], saved = [];
  final input = TextEditingController(),
      focus = FocusNode(),
      scroll = ScrollController();
  final form = GlobalKey<FormState>(),
      field = GlobalKey(),
      feedback = GlobalKey();
  final prefetch = SignVideoPrefetch();
  int index = 0;
  String? pending, error, adviceError;
  bool loading = true, adviceBusy = false, leaving = false;
  bool showFrames = false, practiceOpen = false, exitConfirmed = false;
  LearningService get service => context.read<LearningService>();
  AppRouteExitController? exitGuard;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    exitGuard?.handler = null;
    exitGuard = AppRouteExitScope.maybeOf(context);
    exitGuard?.handler = prepareExit;
  }

  bool get busy => pending != null;
  bool get dirty => !listEquals(answers, saved);
  bool get completed => quiz?['status'] == 'COMPLETED';
  bool get unfinished => quiz?['status'] == 'DRAFT';
  List<LearningRecord> get questions => (quiz?['questions'] as List? ?? [])
      .map((q) => LearningRecord.from(q as Map))
      .toList();
  LearningRecord? get question => questions.isEmpty
      ? null
      : questions[index.clamp(0, questions.length - 1)];
  LearningRecord? get response => question?['response'] is Map
      ? LearningRecord.from(question!['response'] as Map)
      : null;
  bool done(LearningRecord q) {
    final r = q['response'];
    return r is Map &&
        (r['match'] == 'EXACT' ||
            r['match'] == 'SKIPPED' ||
            r['assessment'] != null);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    exitGuard?.handler = null;
    input.dispose();
    focus.dispose();
    scroll.dispose();
    prefetch.dispose();
    super.dispose();
  }

  String message(Object e, String fallback) =>
      e is ApiException ? e.message : fallback;
  bool meaningfulDefinition(String value) =>
      value.trim().isNotEmpty &&
      !RegExp(
        r'mẫu ký hiệu tham khảo|theo nhãn trong dataset|dataset nguồn',
        caseSensitive: false,
      ).hasMatch(value);
  void apply(
    LearningRecord value, {
    bool keepDraft = false,
    bool warmMedia = true,
  }) {
    final local = [...answers];
    quiz = value;
    final restored = value['answers'] as List? ?? [];
    saved = List.generate(
      questions.length,
      (i) => i < restored.length ? '${restored[i]}' : '',
    );
    answers = keepDraft && local.length == saved.length ? local : [...saved];
    syncInput();
    primeImagePreviews(questions);
    if (warmMedia) warm();
  }

  void syncInput() {
    final value = index < answers.length ? answers[index] : '';
    if (input.text != value) {
      input.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  void warm() {
    final list = questions;
    prefetch.warm(
      completed
          ? []
          : [
              if (index < list.length) '${list[index]['videoUrl'] ?? ''}',
              if (index + 1 < list.length)
                '${list[index + 1]['videoUrl'] ?? ''}',
            ],
    );
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await service.quiz(widget.quizId);
      if (!mounted) return;
      apply(value, warmMedia: false);
      final first = questions.indexWhere((q) => !done(q));
      index = first < 0 ? 0 : first;
      syncInput();
      warm();
    } catch (e) {
      if (mounted) error = message(e, 'Chưa tải được bài ôn tập. Hãy thử lại.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void reveal(GlobalKey target) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = target.currentContext;
        if (mounted && context != null) {
          Scrollable.ensureVisible(
            context,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            alignment: .15,
          );
        }
      });
  void top() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) scroll.jumpTo(0);
  });
  Future<void> persist() async {
    if (!dirty) return;
    final snapshot = [...answers];
    await service.saveQuizAnswers(widget.quizId, snapshot);
    if (mounted) saved = snapshot;
  }

  Future<void> hint() async {
    if (busy || question == null || response != null) return;
    setState(() {
      pending = 'hint';
      error = null;
    });
    try {
      final value = await service.quizHint(
        widget.quizId,
        '${question!['entryId']}',
      );
      if (mounted) setState(() => apply(value, keepDraft: true));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = message(e, 'Chưa lấy được gợi ý. Bạn có thể thử lại.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => pending = null);
        reveal(field);
      }
    }
  }

  Future<void> check({bool skip = false}) async {
    if (busy || question == null || response != null) return;
    if (!skip && form.currentState?.validate() != true) {
      focus.requestFocus();
      reveal(field);
      return;
    }
    focus.unfocus();
    setState(() {
      pending = 'check';
      error = null;
    });
    try {
      final value = await service.checkQuizAnswer(
        widget.quizId,
        '${question!['entryId']}',
        input.text,
        skip: skip,
      );
      if (mounted) setState(() => apply(value));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = message(
            e,
            'Chưa kiểm tra được. Câu bạn nhập vẫn được giữ để thử lại.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => pending = null);
        reveal(response == null ? field : feedback);
      }
    }
  }

  Future<void> assess(String value) async {
    if (busy || response == null) return;
    setState(() {
      pending = 'assessment:$value';
      error = null;
    });
    try {
      final updated = await service.assessQuizAnswer(
        widget.quizId,
        '${question!['entryId']}',
        value,
      );
      if (mounted) setState(() => apply(updated));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = message(
            e,
            'Chưa lưu được phần tự đối chiếu. Hãy thử lại.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => pending = null);
    }
  }

  Future<void> move(int next) async {
    if (busy) return;
    focus.unfocus();
    setState(() {
      pending = 'save';
      error = null;
    });
    try {
      await persist();
      if (mounted) {
        setState(() {
          index = next;
          showFrames = false;
          syncInput();
          warm();
        });
      }
      top();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = message(
            e,
            'Chưa lưu được bài. Nội dung đang nhập vẫn được giữ.',
          ),
        );
        reveal(field);
      }
    } finally {
      if (mounted) setState(() => pending = null);
    }
  }

  Future<void> submit() async {
    if (busy) return;
    final missing = questions.indexWhere((q) => !done(q));
    if (missing >= 0) {
      await move(missing);
      return;
    }
    setState(() {
      pending = 'submit';
      error = null;
    });
    try {
      await persist();
      final value = await service.submitQuiz(widget.quizId);
      if (mounted) setState(() => apply(value));
      prefetch.warm([]);
      top();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = message(
            e,
            'Chưa hoàn tất được bài. Kết quả từng từ đã kiểm tra được giữ lại.',
          ),
        );
        top();
      }
    } finally {
      if (mounted) setState(() => pending = null);
    }
  }

  Future<void> restartAfterLibraryUpdate() async {
    if (busy) return;
    setState(() {
      pending = 'restart';
      error = null;
    });
    try {
      final fresh = quiz?['collectionId'] != null
          ? await service.startCollectionQuiz('${quiz!['collectionId']}')
          : await service.startQuiz('${quiz!['topicId']}');
      if (!mounted) return;
      setState(() => exitConfirmed = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) {
        replaceAppRoute(context, '/learn/quiz/${fresh['_id']}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = message(e, 'Chưa mở được lượt ôn mới.'));
      }
    } finally {
      if (mounted) setState(() => pending = null);
    }
  }

  Future<void> leave() async {
    if (await prepareExit() && mounted) backOrHome(context);
  }

  Future<bool> prepareExit() async {
    if (busy || leaving) return false;
    focus.unfocus();
    if (exitConfirmed || !unfinished && !dirty) return true;
    leaving = true;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Rời bài ôn tập?'),
        content: Text(
          unfinished
              ? 'Bạn chưa hoàn tất lượt ôn. Câu đã đối chiếu sẽ được giữ; bạn có thể lưu bài và ôn tiếp sau.'
              : 'Nội dung đang nhập chưa được lưu. Lưu lại để ôn tiếp sau.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tiếp tục ôn'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Lưu & thoát'),
          ),
        ],
      ),
    );
    leaving = false;
    if (!mounted || action == null) return false;
    if (action == 'save') {
      setState(() {
        pending = 'save';
        error = null;
      });
      try {
        await persist();
      } catch (e) {
        if (mounted) {
          setState(() {
            pending = null;
            error = message(e, 'Chưa lưu được bài. Hãy thử lại.');
          });
          reveal(field);
        }
        return false;
      }
    }
    if (!mounted) return false;
    setState(() {
      saved = [...answers];
      pending = null;
      exitConfirmed = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    return mounted;
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
            'Chưa lấy được gợi ý AI. Kết quả ôn tập đã được lưu.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => adviceBusy = false);
    }
  }

  Future<void> practice(LearningRecord q, String word) async {
    if (practiceOpen) return;
    focus.unfocus();
    setState(() => practiceOpen = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => QuizPracticeSheet(
          word: {...q, 'word': word},
          mirrorFactory: widget.mirrorFactory,
        ),
      );
    } finally {
      if (mounted) setState(() => practiceOpen = false);
    }
  }

  Widget feedbackCard(LearningRecord r) {
    final colors = Theme.of(context).colorScheme;
    final exact = r['match'] == 'EXACT', skipped = r['match'] == 'SKIPPED';
    final independent = exact && r['usedHint'] != true;
    final label = independent
        ? 'Bạn đã tự nhớ được'
        : exact
        ? 'Bạn đã tìm ra nghĩa'
        : skipped
        ? 'Cùng học lại từ này'
        : 'Cùng đối chiếu';
    return Semantics(
      container: true,
      liveRegion: true,
      child: AppCard(
        key: feedback,
        color: colors.primaryContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    independent
                        ? Icons.check_circle_outline
                        : Icons.menu_book_outlined,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if ('${r['answer']}'.isNotEmpty)
              Text(
                'Bạn nhập: ${r['answer']}',
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
            const SizedBox(height: 8),
            Text(
              '${r['correctAnswer']}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colors.onPrimaryContainer,
              ),
            ),
            if (meaningfulDefinition('${r['definition'] ?? ''}')) ...[
              const SizedBox(height: 8),
              Text(
                '${r['definition']}',
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
            ],
            if ('${r['usageExample'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Ví dụ: ${r['usageExample']}',
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              independent
                  ? 'Nghĩa bạn nhập khớp từ hoặc tên gọi trong từ điển.'
                  : r['usedHint'] == true && exact
                  ? 'Bạn đã dùng gợi ý. Từ này sẽ được ôn lại để củng cố.'
                  : r['match'] == 'CLOSE'
                  ? 'Câu nhập khá gần đáp án. Hãy kiểm tra dấu, chính tả và ý nghĩa trước khi tự đối chiếu.'
                  : skipped
                  ? 'Không sao. Xem lại mẫu, thử nhớ nghĩa rồi ôn lại sau.'
                  : 'Cách diễn đạt này chưa có trong đáp án. Bạn có thể tự đối chiếu ý nghĩa bên dưới.',
              style: TextStyle(color: colors.onPrimaryContainer),
            ),
            if (!exact && !skipped) ...[
              const SizedBox(height: 16),
              AppButton(
                'Tôi diễn đạt cùng nghĩa',
                busy: pending == 'assessment:SAME_MEANING',
                color: colors.onPrimaryContainer,
                outlined: r['assessment'] != 'SAME_MEANING',
                icon: r['assessment'] == 'SAME_MEANING'
                    ? Icons.check
                    : Icons.compare_arrows,
                onPressed: busy ? null : () => assess('SAME_MEANING'),
              ),
              const SizedBox(height: 8),
              AppButton(
                'Tôi cần ôn thêm',
                busy: pending == 'assessment:REVIEW',
                color: colors.onPrimaryContainer,
                outlined: r['assessment'] != 'REVIEW',
                icon: r['assessment'] == 'REVIEW' ? Icons.check : Icons.refresh,
                onPressed: busy ? null : () => assess('REVIEW'),
              ),
              const SizedBox(height: 8),
              Text(
                'Phần này là tự đánh giá. Từ vẫn ở Ôn tập cho đến khi bạn tự nhớ lại.',
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: colors.onPrimaryContainer,
                minimumSize: const Size(48, 48),
              ),
              onPressed: busy
                  ? null
                  : () => practice(question!, '${r['correctAnswer']}'),
              icon: const Icon(Icons.videocam_outlined),
              label: const Text('Tự thực hành với mẫu'),
            ),
          ],
        ),
      ),
    );
  }

  Widget adviceCard() => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading('Gợi ý ôn trong 5 phút', size: 19),
        const SizedBox(height: 8),
        if (advice == null && !adviceBusy)
          const BodyText(
            'Nhận kế hoạch ngắn, tập trung vào những từ bạn chưa tự nhớ.',
          ),
        if (adviceBusy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const BodyText(
            'Đang chuẩn bị gợi ý. Bạn có thể xem lại kết quả trong lúc chờ.',
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
            'Nhận gợi ý ôn tập',
            busy: adviceBusy,
            icon: Icons.auto_awesome_outlined,
            onPressed: adviceBusy ? null : getAdvice,
          ),
        ],
      ],
    ),
  );

  Widget results() {
    final result = LearningRecord.from(quiz!['result'] as Map);
    final items = (result['items'] as List? ?? [])
        .map((r) => LearningRecord.from(r as Map))
        .toList();
    final summary = result['summary'] as Map?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Heading('Bạn đã hoàn tất lượt ôn', size: 24),
        const SizedBox(height: 8),
        const BodyText(
          'Kết quả ghi nhớ được lưu. Bạn có thể xem lại từng từ và luyện thêm bất cứ lúc nào.',
        ),
        const SizedBox(height: 16),
        if (summary != null)
          AppCard(
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                for (final (key, label) in [
                  ('independent', 'Tự nhớ'),
                  ('assisted', 'Có hỗ trợ'),
                  ('review', 'Cần ôn thêm'),
                ])
                  SizedBox(
                    width: 96,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Heading('${summary[key] ?? 0}', size: 28),
                        Text(label),
                      ],
                    ),
                  ),
              ],
            ),
          )
        else
          AppCard(child: Text('Kết quả đã lưu: ${result['score']} / 10 điểm')),
        const SizedBox(height: 12),
        const BodyText(
          'Từ có gợi ý hoặc tự đối chiếu vẫn ở Ôn tập. Phần này ghi nhận hiểu nghĩa, không chấm động tác.',
        ),
        const SizedBox(height: 20),
        adviceCard(),
        const SizedBox(height: 24),
        const Heading('Những từ vừa ôn', size: 20),
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
                      ExcludeSemantics(
                        child: Icon(
                          item['score'] == 10
                              ? Icons.check_circle_outline
                              : Icons.history,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Heading('${item['word']}', size: 19)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BodyText(
                    item['score'] == 10
                        ? 'Tự nhớ đúng'
                        : item['selfAssessment'] == 'SAME_MEANING'
                        ? 'Bạn tự xác nhận cùng nghĩa · sẽ ôn lại'
                        : item['matchStatus'] == 'EXACT'
                        ? 'Nhớ với gợi ý · sẽ ôn lại'
                        : 'Cần ôn thêm',
                  ),
                  const SizedBox(height: 6),
                  BodyText(
                    'Bạn nhập: ${'${item['selectedAnswer'] ?? item['recognizedLabel'] ?? ''}'.isEmpty ? 'Chưa nhớ' : item['selectedAnswer'] ?? item['recognizedLabel']}',
                  ),
                  if (item['applied'] == false) ...[
                    const SizedBox(height: 8),
                    const BodyText(
                      'Tiến độ đã thay đổi trong lúc làm bài; giữ trạng thái mới nhất.',
                    ),
                  ],
                  if (i < questions.length)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Xem mẫu và ý nghĩa'),
                      children: [
                        LearningWordContent(
                          {...questions[i], ...item},
                          quizControls: true,
                          pauseVideo: practiceOpen,
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              practice(questions[i], '${item['word']}'),
                          icon: const Icon(Icons.videocam_outlined),
                          label: const Text('Tự thực hành'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget questionView(bool keyboard) {
    final q = question!, r = response;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 8,
          children: [
            Heading('Từ ${index + 1} / ${questions.length}', size: 20),
            Text(
              'Đã đối chiếu ${questions.where(done).length}/${questions.length}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: questions.where(done).length / questions.length,
        ),
        const SizedBox(height: 16),
        const Heading('Ký hiệu này có nghĩa là gì?', size: 22),
        const SizedBox(height: 8),
        if (!keyboard)
          const BodyText('Xem mẫu, thử tự nhớ rồi nhập nghĩa bên dưới.'),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LearningWordContent(
              {...q, 'word': r?['correctAnswer'] ?? 'Ký hiệu đang ôn'},
              key: ValueKey('recall-media-${q['entryId']}'),
              showMeaning: false,
              hideQuizLabels: r == null,
              quizControls: true,
              previewHeight: keyboard ? 128 : 208,
              showFrames: !keyboard && showFrames,
              pauseVideo: keyboard || practiceOpen,
            ),
          ),
        ),
        if (!keyboard && (q['imageUrls'] as List? ?? []).length > 1)
          Semantics(
            expanded: showFrames,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => setState(() => showFrames = !showFrames),
              icon: Icon(
                showFrames ? Icons.expand_less : Icons.photo_library_outlined,
              ),
              label: Text(
                showFrames ? 'Thu gọn chuỗi ảnh' : 'Xem các bước bằng ảnh',
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (r != null)
          feedbackCard(r)
        else
          Form(
            key: form,
            child: Column(
              key: field,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (q['hint'] != null) ...[
                  AppCard(
                    color: colors.secondaryContainer,
                    child: Text(
                      '${q['hint']}',
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  key: const ValueKey('quiz-recall-answer'),
                  controller: input,
                  focusNode: focus,
                  textInputAction: TextInputAction.done,
                  maxLength: 200,
                  minLines: 1,
                  maxLines: 3,
                  readOnly:
                      pending == 'check' ||
                      pending == 'submit' ||
                      pending == 'save',
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Nghĩa bạn nhớ',
                    hintText: 'Nhập từ hoặc cụm từ tiếng Việt',
                    counterText: '',
                  ),
                  onChanged: (value) => setState(() {
                    answers[index] = value;
                    error = null;
                  }),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nhập nghĩa bạn nhớ, hoặc chọn Chưa nhớ.'
                      : null,
                  onFieldSubmitted: (_) => check(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: busy || q['hint'] != null ? null : hint,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.lightbulb_outline),
                      label: Text(
                        pending == 'hint'
                            ? 'Đang lấy gợi ý…'
                            : q['hint'] != null
                            ? 'Đã dùng gợi ý'
                            : 'Gợi ý',
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => check(skip: true),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      child: const Text('Chưa nhớ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Notice(error!)),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget? footer() {
    if (loading || quiz == null) return null;
    if (quiz!['libraryChanged'] == true && quiz!['status'] == 'ABANDONED') {
      return AppButton(
        'Bắt đầu lượt ôn mới',
        busy: busy,
        onPressed: busy ? null : restartAfterLibraryUpdate,
      );
    }
    if (completed || quiz!['kind'] != 'VIDEO_RECALL' || question == null) {
      return AppButton(
        quiz?['collectionId'] != null ? 'Về bộ sưu tập' : 'Về chủ đề',
        icon: Icons.arrow_back,
        onPressed: () {
          if (quiz?['collectionId'] != null && Navigator.of(context).canPop()) {
            Navigator.pop(context);
            return;
          }
          replaceAppRoute(
            context,
            quiz?['collectionId'] != null
                ? '/collections/${quiz!['collectionId']}'
                : '/learn/topic/${quiz!['topicId']}?study=1',
          );
        },
      );
    }
    final checked = response != null, ready = done(question!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (checked && !ready) ...[
          const Text('Chọn cách tự đối chiếu ở trên để tiếp tục.'),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            IconButton(
              tooltip: 'Từ trước',
              onPressed: busy || index == 0 ? null : () => move(index - 1),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppButton(
                pending == 'check'
                    ? 'Đang đối chiếu…'
                    : pending == 'submit'
                    ? 'Đang lưu kết quả…'
                    : pending == 'save'
                    ? 'Đang lưu bài…'
                    : !checked
                    ? 'Kiểm tra nghĩa'
                    : index == questions.length - 1
                    ? 'Hoàn tất lượt ôn'
                    : 'Từ tiếp',
                busy: const ['check', 'submit', 'save'].contains(pending),
                icon: !checked
                    ? Icons.check
                    : index == questions.length - 1
                    ? Icons.done_all
                    : Icons.arrow_forward,
                onPressed: busy || checked && !ready
                    ? null
                    : () {
                        if (!checked) {
                          check();
                        } else if (index == questions.length - 1) {
                          submit();
                        } else {
                          move(index + 1);
                        }
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final colors = Theme.of(context).colorScheme;
    final action = footer();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading) const LinearProgressIndicator(),
        if (quiz == null && error != null) ...[
          Notice(error!),
          TextButton(onPressed: load, child: const Text('Thử lại')),
        ],
        if (!loading && quiz != null)
          if (completed && quiz!['result'] is Map)
            results()
          else if (quiz!['libraryChanged'] == true &&
              quiz!['status'] == 'ABANDONED')
            const Notice(
              'Thư viện ký hiệu vừa được cập nhật. Hãy bắt đầu lượt ôn mới để dùng ảnh, video và đáp án hiện tại. Kết quả các lượt đã hoàn tất vẫn được giữ.',
            )
          else if (quiz!['kind'] != 'VIDEO_RECALL')
            const Notice(
              'Đây là lượt ôn của phiên bản trước. Về chủ đề để bắt đầu bài tự nhớ nghĩa mới.',
            )
          else if (question == null)
            const Notice('Chưa có từ để ôn. Hãy về chủ đề để thử lại.')
          else
            questionView(keyboard),
      ],
    );
    return PopScope<Object?>(
      canPop: !busy && (exitConfirmed || !unfinished && !dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy && (unfinished || dirty)) leave();
      },
      child: AppPage(
        title: 'Ôn ký hiệu',
        contentMaxWidth: 1000,
        scroll: false,
        padding: EdgeInsets.zero,
        onBack: leave,
        backEnabled: !busy,
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final inlineAction = constraints.maxHeight < 240 * textScale;
              final gutter = constraints.maxWidth < 360 ? 16.0 : 20.0;
              final body = SingleChildScrollView(
                controller: scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    content,
                    if (inlineAction && action != null) action,
                  ],
                ),
              );
              return Column(
                children: [
                  Expanded(child: body),
                  if (!inlineAction && action != null)
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border(
                          top: BorderSide(color: colors.outlineVariant),
                        ),
                      ),
                      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 12),
                      child: action,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
