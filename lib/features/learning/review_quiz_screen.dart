import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/api/api_exception.dart';
import '../../services/api/api_config.dart';
import '../../services/learning/learning_service.dart';
import '../../services/sign_ai/camera_capture.dart';
import '../../services/sign_ai/media_access_error.dart';
import '../../services/sign_ai/sign_ai_access.dart';
import '../../services/sign_ai/sign_ai_config.dart';
import '../../widgets/ui.dart';
import 'learning_widgets.dart';
import 'quiz_camera_connection.dart';

class ReviewQuizScreen extends StatefulWidget {
  const ReviewQuizScreen({
    super.key,
    required this.quizId,
    this.cameraFactory = createSignCamera,
    this.ticketLoader = loadAiStreamTicket,
    this.channelFactory = WebSocketChannel.connect,
  });
  final String quizId;
  final SignCamera Function({required bool front}) cameraFactory;
  final Future<String> Function() ticketLoader;
  final WebSocketChannel Function(Uri) channelFactory;
  @override
  State<ReviewQuizScreen> createState() => _ReviewQuizScreenState();
}

class _ReviewQuizScreenState extends State<ReviewQuizScreen> {
  LearningRecord? quiz;
  SignCamera? camera;
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  StreamSubscription<LocalHandObservation>? localSubscription;
  Timer? watchdog;
  final clock = Stopwatch()..start();
  int lastResponse = 0, lastObservationSend = -1000;
  num lastObservationStamp = -1000, pendingObservation = -1;
  LocalHandObservation? waitingObservation;
  bool liveObservations = false;
  int? hands;
  int index = 0, sequence = 0, cameraGeneration = 0, streamProtocol = 1;
  bool loading = true, busy = false, startingCamera = false;
  bool stoppingCamera = false;
  bool cameraReady = false, framePending = false, previewReady = false;
  String? error, cameraError, confirmed;
  LearningService get service => context.read<LearningService>();
  List<LearningRecord> get questions => (quiz?['questions'] as List? ?? [])
      .map((q) => LearningRecord.from(q as Map))
      .toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    unawaited(_stopCamera());
    super.dispose();
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
      quiz = value;
      final list = questions;
      final unanswered = list.indexWhere(
        (q) => '${q['recognizedLabel'] ?? ''}'.isEmpty,
      );
      index = unanswered >= 0
          ? unanswered
          : (list.isEmpty ? 0 : list.length - 1);
    } catch (e) {
      if (mounted) {
        error = e is ApiException ? e.message : 'Chưa tải được bài ôn tập.';
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _startCamera() async {
    if (startingCamera || stoppingCamera || camera != null) return;
    final generation = ++cameraGeneration;
    var stage = 'camera';
    setState(() {
      startingCamera = true;
      cameraError = null;
      confirmed = null;
      hands = null;
    });
    SignCamera? created;
    try {
      created = widget.cameraFactory(front: true);
      camera = created;
      await created.initialize();
      if (!mounted || generation != cameraGeneration) {
        await created.close();
        return;
      }
      setState(() => previewReady = true);
      if (created is LocalTrackingCamera) {
        localSubscription = (created as LocalTrackingCamera).localTracking
            .listen((observation) {
              if (mounted && generation == cameraGeneration) {
                _sendObservation(observation);
              }
            });
      }
      stage = 'service';
      final uri = await quizCameraSocketUri(
        serviceUrl: SignAiConfig.defaultUrl,
        gatewayUrl: SignAiConfig.gatewayUrl,
        ticketLoader: widget.ticketLoader,
      );
      if (!mounted || generation != cameraGeneration) return;
      final socket = widget.channelFactory(uri);
      channel = socket;
      await socket.ready.timeout(const Duration(seconds: 15));
      if (!mounted || generation != cameraGeneration) {
        await socket.sink.close();
        return;
      }
      subscription = socket.stream.listen(
        (data) {
          if (mounted && generation == cameraGeneration) _onMessage(data);
        },
        onError: (_) => _cameraFailure('Mất kết nối dịch vụ nhận diện.'),
        onDone: () {
          if (cameraReady) _cameraFailure('Dịch vụ nhận diện đã ngắt kết nối.');
        },
      );
      socket.sink.add(
        jsonEncode({
          'mode': 'words',
          'vision': false,
          'token': SignAiConfig.token,
        }),
      );
      sequence = 0;
      framePending = false;
      lastObservationStamp = -1000;
      pendingObservation = -1;
      waitingObservation = null;
      lastResponse = clock.elapsedMilliseconds;
      await created.start((frame) {
        if (!mounted || !cameraReady || framePending) return;
        framePending = true;
        socket.sink.add(
          frame.packet(sequence++, DateTime.now().millisecondsSinceEpoch),
        );
      }, () => mounted && cameraReady && !framePending);
      if (!mounted || generation != cameraGeneration) return;
      watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
        if (clock.elapsedMilliseconds - lastResponse > 15000) {
          _cameraFailure(
            'AI chưa trả kết quả từ camera trong 15 giây. Hãy thử kết nối lại.',
          );
        }
      });
      if (mounted) setState(() => startingCamera = false);
    } catch (e) {
      if (!mounted || generation != cameraGeneration) return;
      await _stopCamera();
      if (mounted) {
        setState(() {
          startingCamera = false;
          cameraError = stage == 'camera'
              ? (e is MediaAccessException
                    ? e.message
                    : mediaAccessError(e.toString()).message)
              : (e is ApiException
                    ? e.message
                    : 'Camera đã mở nhưng chưa kết nối được dịch vụ nhận diện. Hãy thử kết nối lại.');
        });
      }
    }
  }

  void _sendObservation(LocalHandObservation observation) {
    final measured = observation.handObservation;
    final stamp = measured?['timestamp_ms'];
    if (!cameraReady ||
        !liveObservations ||
        measured == null ||
        stamp is! num) {
      return;
    }
    final now = clock.elapsedMilliseconds;
    if (pendingObservation >= 0 && now - lastObservationSend < 1000) {
      waitingObservation = observation;
      return;
    }
    if (stamp - lastObservationStamp < 66) return;
    waitingObservation = null;
    pendingObservation = stamp;
    lastObservationStamp = stamp;
    lastObservationSend = now;
    channel?.sink.add(
      jsonEncode({'type': 'hand_observation', 'observation': measured}),
    );
  }

  void _onMessage(dynamic data) {
    if (!mounted) return;
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      if (message['type'] == 'error') {
        _cameraFailure(
          message['message']?.toString() ?? 'Dịch vụ nhận diện gặp lỗi.',
        );
      } else if (message['type'] == 'ready') {
        liveObservations = message['live_word_observations'] == true;
        streamProtocol = (message['stream_protocol'] as num?)?.toInt() ?? 1;
        setState(() {
          cameraReady = true;
          startingCamera = false;
          cameraError = null;
        });
      } else if (message['type'] == 'frame_received') {
        if (message['sequence'] == sequence - 1) framePending = false;
      } else if (message['type'] == 'observation_received') {
        if (message['timestamp_ms'] == pendingObservation) {
          pendingObservation = -1;
          final waiting = waitingObservation;
          waitingObservation = null;
          if (waiting != null) _sendObservation(waiting);
        }
      } else if (message['type'] == 'result') {
        lastResponse = clock.elapsedMilliseconds;
        final activeCamera = camera;
        if (activeCamera is ForegroundTrackingCamera &&
            message['foreground_context'] is List &&
            message['timestamp_ms'] is num) {
          (activeCamera as ForegroundTrackingCamera).updateTrackingContext(
            message['foreground_context'] as List,
            (message['timestamp_ms'] as num).round(),
          );
        }
        if (streamProtocol < 2) {
          framePending = false;
        }
        final value = message['confirmed'] as String?;
        final count = (message['hands'] as num?)?.toInt() ?? 0;
        if (count != hands || (confirmed == null && value != null)) {
          setState(() {
            hands = count;
            if (confirmed == null && value != null && value.trim().isNotEmpty) {
              confirmed = value;
            }
          });
        }
      }
    } catch (_) {
      _cameraFailure(
        'Phản hồi nhận diện không hợp lệ. Hãy kết nối lại camera.',
      );
    }
  }

  void _cameraFailure(String message) {
    if (!mounted) return;
    unawaited(_stopCamera());
    setState(() {
      cameraError = message;
      cameraReady = false;
    });
  }

  Future<void> _stopCamera() async {
    watchdog?.cancel();
    watchdog = null;
    final local = localSubscription;
    localSubscription = null;
    cameraGeneration++;
    cameraReady = false;
    previewReady = false;
    startingCamera = false;
    framePending = false;
    liveObservations = false;
    final sub = subscription, socket = channel, activeCamera = camera;
    subscription = null;
    channel = null;
    camera = null;
    await local?.cancel();
    await sub?.cancel();
    try {
      await activeCamera?.close();
    } catch (_) {}
    try {
      await socket?.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _retrySign() async {
    if (busy || startingCamera || stoppingCamera) return;
    setState(() => busy = true);
    await _restartForQuestion();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _restartForQuestion() async {
    await _stopCamera();
    if (!mounted) return;
    setState(() {
      confirmed = null;
      hands = null;
    });
    // A fresh inference session cannot reuse the previous question's held sign.
    await _startCamera();
  }

  Future<void> _stopByUser() async {
    if (stoppingCamera) return;
    setState(() {
      stoppingCamera = true;
      confirmed = null;
      cameraError = null;
    });
    await _stopCamera();
    if (mounted) setState(() => stoppingCamera = false);
  }

  Future<void> _recordAndAdvance() async {
    final list = questions;
    if (busy || list.isEmpty || confirmed == null) return;
    final isLastQuestion = index == list.length - 1;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final current = list[index];
      final value = await service.saveQuizCapture(
        widget.quizId,
        entryId: '${current['entryId']}',
        recognizedLabel: confirmed!,
      );
      if (!mounted) return;
      setState(() {
        quiz = value;
        if (!isLastQuestion) {
          index++;
          confirmed = null;
        }
      });
      if (isLastQuestion) {
        await _submit();
      } else {
        await _restartForQuestion();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa lưu được kết quả camera.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    try {
      final value = await service.submitQuiz(widget.quizId);
      if (mounted) setState(() => quiz = value);
      await _stopCamera();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ApiException
              ? e.message
              : 'Chưa hoàn tất được bài ôn tập.',
        );
      }
    }
  }

  Widget _cameraPanel(LearningRecord question) {
    final sample = '${question['thumbnailUrl'] ?? ''}';
    final images = question['imageUrls'] as List? ?? const [];
    final reference = sample.isNotEmpty
        ? sample
        : (images.isEmpty ? '' : '${images.first}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: previewReady ? camera!.aspectRatio : 4 / 3,
            child: previewReady
                ? camera!.preview()
                : Container(
                    color: const Color(0xFF111827),
                    child: reference.isNotEmpty
                        ? Image.network(
                            ApiConfig.mediaUrl(reference),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const _CameraPlaceholder(
                              message: 'Mẫu ký hiệu',
                            ),
                          )
                        : const _CameraPlaceholder(
                            message: 'Bật camera để thực hiện ký hiệu',
                          ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (!previewReady)
          AppButton(
            'Mở camera nhận diện',
            icon: Icons.camera_alt_outlined,
            busy: startingCamera || stoppingCamera,
            onPressed: startingCamera || stoppingCamera ? null : _startCamera,
          )
        else
          AppCard(
            child: Row(
              children: [
                Icon(
                  cameraReady ? Icons.wifi_tethering : Icons.hourglass_top,
                  color: cameraReady ? const Color(0xFF008F7A) : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cameraReady ? 'AI đã kết nối' : 'Đang kết nối AI',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      BodyText(
                        cameraReady
                            ? (confirmed == null
                                  ? (hands == null
                                        ? 'Đang chờ khung hình đầu tiên từ camera...'
                                        : hands == 0
                                        ? 'Chưa thấy tay. Đưa trọn tay và mặt vào khung hình.'
                                        : 'Đã thấy $hands tay. Làm trọn ký hiệu “${question['word']}”, rồi hạ tay để kết thúc động tác.')
                                  : 'Nhận diện: $confirmed')
                            : 'Camera đã bật. Đang chờ dịch vụ nhận diện...',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (camera != null || startingCamera || stoppingCamera) ...[
          const SizedBox(height: 10),
          AppButton(
            'Dừng camera',
            icon: Icons.stop_circle_outlined,
            outlined: true,
            busy: stoppingCamera,
            onPressed: stoppingCamera ? null : _stopByUser,
          ),
        ],
        if (cameraError != null) ...[
          const SizedBox(height: 8),
          Notice(cameraError!),
          TextButton.icon(
            onPressed: _startCamera,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử kết nối lại'),
          ),
        ],
      ],
    );
  }

  Widget resultView(LearningRecord result) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Heading('Kết quả ôn tập', size: 24),
      const SizedBox(height: 12),
      const SignVoiceBadge('Đánh giá bằng nhận diện ký hiệu'),
      const SizedBox(height: 16),
      Heading('${result['score']} / 10 điểm', size: 28),
      const SizedBox(height: 12),
      BodyText('${result['feedback']}'),
      const SizedBox(height: 12),
      const Notice(
        'Từng ký hiệu camera nhận diện đúng được tính 10 điểm và chuyển sang Đã nhớ. Các từ chưa khớp vẫn ở mục Ôn tập.',
      ),
      const SizedBox(height: 16),
      for (final item in (result['items'] as List? ?? []))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Heading('${item['word']} · ${item['score']}/10', size: 18),
                const SizedBox(height: 8),
                BodyText('Camera nhận diện: ${item['recognizedLabel']}'),
                const SizedBox(height: 8),
                BodyText('${item['feedback']}'),
                const SizedBox(height: 10),
                Text(
                  item['applied'] == true
                      ? 'Trạng thái: ${learningLabels[item['stage']]}'
                      : 'Tiến độ đã đổi trong lúc làm bài; giữ trạng thái mới nhất.',
                ),
              ],
            ),
          ),
        ),
      AppButton(
        'Về chủ đề',
        icon: Icons.arrow_back,
        onPressed: () {
          Navigator.pushReplacementNamed(
            context,
            '/learn/topic/${quiz!['topicId']}?study=1',
          );
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final result = quiz?['result'];
    final list = questions;
    final question = list.isEmpty
        ? null
        : list[index.clamp(0, list.length - 1).toInt()];
    final recognized = confirmed;
    String normalize(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final matches =
        question != null &&
        recognized != null &&
        [
          question['word'],
          ...question['aliases'] as List? ?? [],
        ].any((word) => normalize('$word') == normalize(recognized));
    return AppPage(
      title: 'Quiz ôn tập',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[Notice(error!), const SizedBox(height: 12)],
          if (!loading && result is Map)
            resultView(LearningRecord.from(result))
          else if (!loading && question != null) ...[
            Heading('Câu ${index + 1} / ${list.length}', size: 21),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: (index + 1) / list.length),
            const SizedBox(height: 20),
            Heading('${question['word']}', size: 28),
            const SizedBox(height: 8),
            BodyText('${question['prompt']}'),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Xem video hoặc ảnh mẫu'),
              children: [LearningWordContent(question, showMeaning: false)],
            ),
            const SizedBox(height: 16),
            _cameraPanel(question),
            const SizedBox(height: 14),
            if (recognized != null) ...[
              SignVoiceBadge(
                matches
                    ? 'Đúng ký hiệu “${question['word']}”'
                    : 'Chưa khớp: AI nhận diện “$recognized”',
                color: matches
                    ? const Color(0xFF15803D)
                    : const Color(0xFFB45309),
              ),
              TextButton.icon(
                onPressed: busy ? null : _retrySign,
                icon: const Icon(Icons.replay),
                label: const Text('Làm lại ký hiệu'),
              ),
              const SizedBox(height: 12),
            ],
            const BodyText(
              'Bạn có thể xem hình hoặc video mẫu, sau đó thực hiện ký hiệu trước camera. Kết quả được lưu khi chuyển câu.',
            ),
            const SizedBox(height: 16),
            AppButton(
              index == list.length - 1 ? 'Lưu & hoàn tất' : 'Lưu & câu tiếp',
              icon: index == list.length - 1
                  ? Icons.check
                  : Icons.arrow_forward,
              busy: busy,
              onPressed: busy || recognized == null ? null : _recordAndAdvance,
            ),
            if (index > 0)
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          index--;
                        });
                        await _restartForQuestion();
                        if (mounted) setState(() => busy = false);
                      },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Câu trước'),
              ),
          ],
        ],
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.front_hand_outlined,
            size: 48,
            color: Colors.white70,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}
