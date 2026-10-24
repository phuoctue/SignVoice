import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/app_state.dart';
import '../../core/navigation.dart';
import '../../services/sign_ai/camera_capture.dart';
import '../../services/sign_ai/camera_diagnostic.dart';
import '../../services/sign_ai/diagnostic_export.dart';
import '../../services/sign_ai/media_access_error.dart';
import '../../services/sign_ai/observation_pacer.dart';
import '../../services/sign_ai/sign_ai_config.dart';
import '../../services/sign_ai/sign_ai_access.dart';
import '../../services/sign_ai/speech_output.dart';
import '../../services/sign_ai/stream_timing.dart';
import '../../widgets/device_permission_page.dart';

const _ink = Color(0xFF111827);
const _card = Color(0xFF202938);
const _blue = Color(0xFF4560F0);
const _green = Color(0xFF43A047);
const _red = Color(0xFFE34B43);
const _muted = Color(0xFFAAB7CA);

class LiveCameraScreen extends StatefulWidget {
  const LiveCameraScreen({
    super.key,
    this.cameraFactory = createSignCamera,
    this.channelFactory = WebSocketChannel.connect,
    this.ticketLoader = loadAiStreamTicket,
    this.diagnosticsEnabled = const bool.fromEnvironment('CAMERA_DIAGNOSTICS'),
    this.diagnosticExporter = exportDiagnostic,
  });
  final SignCamera Function({required bool front}) cameraFactory;
  final WebSocketChannel Function(Uri) channelFactory;
  final Future<String> Function() ticketLoader;
  final bool diagnosticsEnabled;
  final Future<String> Function(String) diagnosticExporter;
  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

class _LiveCameraScreenState extends State<LiveCameraScreen>
    with WidgetsBindingObserver {
  SignCamera? _camera;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<LocalHandObservation>? _localSubscription;
  final _localHands = ValueNotifier<LocalHandObservation?>(null);
  int _localReceived = -10000;
  Timer? _localStale;
  final _clock = Stopwatch()..start();
  final _diagnostic = CameraDiagnostic();
  bool _diagnosticBusy = false;
  final _speech = SpeechOutput();
  String _url = SignAiConfig.defaultUrl, _mode = 'words', _status = 'idle';
  String? _error, _confirmed;
  String _landmarkSource = 'cpu';
  bool _localTrackingActive = false;
  int _lastUiUpdate = -1000;
  String _wordEngine = '';
  double _embeddingWeight = 0;
  bool _front = true, _opening = false, _ready = false, _pending = false;
  bool _cameraReady = false, _cameraError = false, _starting = false;
  bool _consent = false;
  bool _liveObservations = false;
  bool _liveWordObservations = false;
  int _lastObservationSend = -1000;
  num _lastObservationStamp = -1000;
  final _observationPacer = ObservationPacer();
  static const _phaseObservationPacing = bool.fromEnvironment(
    'CAMERA_PHASE_PACING',
  );
  num? _pendingObservation;
  LocalHandObservation? _waitingObservation;
  bool _autoSpeak = false, _showOpenCv = false, _resume = false;
  int _generation = 0, _sequence = 0, _lastSend = -100, _lastResult = 0;
  int _protocol = 1, _hands = 0, _classes = 0, _dropped = 0, _lastEvent = 0;
  double _processingMs = 0, _fps = 0;
  StreamTiming _streamTiming = StreamTiming();
  List<dynamic> _landmarks = [];
  Map<String, dynamic> _opencv = {};
  Map<String, dynamic> _inference = {};
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadUrl());
  }

  Future<void> _loadUrl() async {
    // Explicit launch configuration must take priority over old saved URLs.
    final prefs = await SharedPreferences.getInstance();
    if (mounted && !_opening && _camera == null) {
      setState(() {
        if (SignAiConfig.configuredUrl.isEmpty) {
          _url = prefs.getString('sign_ai_service_url') ?? _url;
        }
        final mode = prefs.getString('sign_ai_mode');
        if (['words', 'letters', 'digits', 'all'].contains(mode)) _mode = mode!;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_opening) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _resume = _camera != null;
      unawaited(_stop());
      unawaited(_speech.stop());
    } else if (state == AppLifecycleState.resumed && _resume) {
      _resume = false;
      if (mounted) setState(() => _consent = false);
    }
  }

  Future<void> _stop() async {
    _generation++;
    _ready = false;
    _pending = false;
    _watchdog?.cancel();
    _localStale?.cancel();
    final localSubscription = _localSubscription;
    _localSubscription = null;
    _localHands.value = null;
    _localTrackingActive = false;
    await localSubscription?.cancel();
    final camera = _camera, channel = _channel, subscription = _subscription;
    _camera = null;
    _cameraReady = false;
    _channel = null;
    _subscription = null;
    if (mounted) {
      setState(() {
        _opening = false;
        _landmarks = [];
        _opencv = {};
        _inference = {};
        _confirmed = null;
        _hands = 0;
        _status = 'idle';
      });
    }
    await subscription?.cancel();
    try {
      await camera?.close();
    } catch (_) {
      /* Released by OS. */
    }
    try {
      await channel?.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Transport already closed. */
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    var stage = 'camera';
    try {
      await _stop();
      if (!mounted) return;
      final generation = _generation;
      setState(() {
        _opening = true;
        _error = null;
        _cameraError = false;
        _status = 'requesting_camera';
      });
      // Request actual device permission before depending on the AI server.
      final camera = widget.cameraFactory(front: _front);
      _camera = camera;
      if (camera is HandTrackingModeCamera) {
        (camera as HandTrackingModeCamera).setTrackingMode(_mode);
      }
      await camera.initialize();
      if (!mounted || generation != _generation) {
        await camera.close();
        return;
      }
      if (camera is LocalTrackingCamera) {
        _localSubscription = (camera as LocalTrackingCamera).localTracking
            .listen((observation) {
              if (!mounted || generation != _generation) return;
              _localReceived = _clock.elapsedMilliseconds;
              if (_diagnostic.recording) {
                _diagnostic.add({
                  'kind': 'local',
                  'client_received_ms': _localReceived,
                  'timestamp_ms':
                      observation.timestampMs ??
                      observation.handObservation?['timestamp_ms'],
                  'hands': observation.landmarks.length,
                  'fps': observation.fps,
                  'processing_ms': observation.processingMs,
                  'capture_source': observation.captureSource,
                  'capture_age_ms': observation.captureAgeMs,
                  'initialization_ms': observation.initializationMs,
                });
              }
              if (observation.captureSource == 'initializing') {
                _localStale?.cancel();
                _localHands.value = observation;
                return;
              }
              _localTrackingActive =
                  observation.captureSource != 'unavailable' &&
                  (observation.fps > 0 || observation.processingMs > 0);
              _localHands.value = _localTrackingActive ? observation : null;
              _sendObservation(observation);
              _localStale?.cancel();
              _localStale = Timer(const Duration(milliseconds: 180), () {
                if (mounted && generation == _generation) {
                  _localHands.value = null;
                }
              });
            });
      }
      setState(() {
        _cameraReady = true;
        _front = camera.front;
        _status = 'connecting';
      });
      final state = context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
      state?.update(() => state.cameraAllowed = true);
      stage = 'service';
      if (state?.guest == true) _url = SignAiConfig.gatewayUrl;
      var socketUri = SignAiConfig.socketUri(_url);
      final gateway = Uri.parse(SignAiConfig.gatewayUrl);
      if (socketUri.host == gateway.host &&
          socketUri.port == gateway.port &&
          socketUri.path == '/sign-ai/v1/stream') {
        socketUri = socketUri.replace(
          queryParameters: {'ticket': await widget.ticketLoader()},
        );
      }
      if (!mounted || generation != _generation) return;
      final channel = widget.channelFactory(socketUri);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) {
        await channel.sink.close();
        return;
      }
      _lastEvent = 0;
      _protocol = 1;
      _liveObservations = false;
      _liveWordObservations = false;
      _pendingObservation = null;
      _waitingObservation = null;
      _lastObservationSend = -1000;
      _lastObservationStamp = -1000;
      _observationPacer.reset();
      channel.sink.add(
        jsonEncode({
          'mode': _mode,
          'vision': false,
          'token': SignAiConfig.token,
          if (_diagnostic.recording) 'diagnostic': true,
        }),
      );
      _subscription = channel.stream.listen(
        (data) {
          if (!mounted || generation != _generation) return;
          try {
            _message(jsonDecode(data as String) as Map<String, dynamic>);
          } catch (_) {
            _fail('Phản hồi AI không hợp lệ. Hãy kết nối lại.');
          }
        },
        onError: (_) {
          if (mounted && generation == _generation) {
            _fail('Mất kết nối service AI.');
          }
        },
        onDone: () {
          if (mounted && generation == _generation) {
            _fail('Service AI đã ngắt kết nối.');
          }
        },
      );
      _sequence = 0;
      _streamTiming = StreamTiming();
      _lastSend = -100;
      _lastResult = _clock.elapsedMilliseconds;
      stage = 'camera_stream';
      await camera.start((frame) {
        if (generation != _generation || !_canSend()) return;
        _pending = true;
        _lastSend = _clock.elapsedMilliseconds;
        _streamTiming.sent(
          _sequence,
          _lastSend,
          encodingMs: frame.metadata['encode_ms'] as num?,
        );
        _diagnostic.sent(_sequence, _lastSend);
        if (_diagnostic.recording) {
          _diagnostic.add({
            'kind': 'frame',
            'sequence': _sequence,
            'timestamp_ms': frame.timestampMs ?? _lastSend,
            'client_sent_ms': _lastSend,
            for (final key in const ['format', 'width', 'height', 'encode_ms'])
              if (frame.metadata.containsKey(key)) key: frame.metadata[key],
          });
        }
        channel.sink.add(frame.packet(_sequence++, _lastSend));
      }, () => generation == _generation && _canSend());
      if (!mounted || generation != _generation) return;
      setState(() {
        _front = camera.front;
        _opening = false;
      });
      _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_localHands.value?.captureSource != 'initializing' &&
            _clock.elapsedMilliseconds - _localReceived > 700) {
          _localHands.value = null;
        }
        if (_clock.elapsedMilliseconds - _lastResult > 15000 ||
            (_pending && _clock.elapsedMilliseconds - _lastSend > 15000)) {
          _fail('Service AI phản hồi quá chậm. Hãy thử lại.');
        }
      });
    } catch (error) {
      if (mounted) {
        if (stage == 'service') {
          _fail(
            error is FormatException
                ? error.message
                : 'Camera đã mở. Chưa kết nối được service AI tại $_url. '
                      'Bật Chay_AI_Service.bat; mặc định AI dùng cổng 8001, '
                      'giao diện Flutter dùng cổng 8080.',
          );
        } else {
          final failure = error is MediaAccessException
              ? error
              : mediaAccessError(error.toString());
          _fail(failure.message, cameraError: true);
        }
      }
    } finally {
      _starting = false;
    }
  }

  // Camera capture owns pacing. Applying a second timer after JPEG encoding
  // would reject the next fresh frame when encoding consumes part of its period.
  bool _canSend() => mounted && _ready && !_pending;

  void _sendObservation(LocalHandObservation observation) {
    final measured = observation.handObservation;
    final now = _clock.elapsedMilliseconds;
    if (!_ready ||
        !((_mode == 'letters' || _mode == 'digits')
            ? _liveObservations
            : _liveWordObservations) ||
        measured == null) {
      return;
    }
    if (_pendingObservation != null && now - _lastObservationSend < 1000) {
      _waitingObservation =
          observation; // newest only; never a queue of old poses
      return;
    }
    final stamp = measured['timestamp_ms'] as num;
    if (_phaseObservationPacing && _mode == 'words') {
      if (!_observationPacer.claim(stamp)) return;
    } else if (stamp - _lastObservationStamp < 66) {
      return;
    }
    _waitingObservation = null;
    _lastObservationStamp = stamp;
    _pendingObservation = stamp;
    _lastObservationSend = now;
    if (_diagnostic.recording) {
      _diagnostic.add({
        'kind': 'observation_send',
        'timestamp_ms': stamp,
        'client_sent_ms': now,
      });
    }
    _channel?.sink.add(
      jsonEncode({'type': 'hand_observation', 'observation': measured}),
    );
  }

  Future<void> _releaseTransport(
    StreamSubscription<dynamic>? subscription,
    WebSocketChannel? channel,
  ) async {
    await subscription?.cancel();
    try {
      await channel?.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Already closed. */
    }
  }

  void _fail(String error, {bool cameraError = false}) {
    if (!mounted) return;
    if (cameraError) {
      unawaited(_stop());
      final state = context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
      state?.update(() => state.cameraAllowed = false);
    } else {
      // Keep the preview usable even when recognition is offline.
      _generation++;
      _ready = false;
      _pending = false;
      _watchdog?.cancel();
      final channel = _channel, subscription = _subscription;
      _channel = null;
      _subscription = null;
      unawaited(_releaseTransport(subscription, channel));
    }
    setState(() {
      _error = error;
      _cameraError = cameraError;
      _opening = false;
      _status = 'error';
      _confirmed = null;
      _landmarks = [];
      _opencv = {};
      _inference = {};
      _hands = 0;
    });
  }

  void _message(Map<String, dynamic> message) {
    _diagnostic.received(message, _clock.elapsedMilliseconds);
    if (_diagnostic.recording &&
        (message['type'] == 'frame_received' ||
            message['type'] == 'observation_received')) {
      _diagnostic.add({
        'kind': message['type'],
        'sequence': message['sequence'],
        'timestamp_ms': message['timestamp_ms'],
        'client_received_ms': _clock.elapsedMilliseconds,
      });
    }
    if (message['type'] == 'error') {
      _fail(message['message']?.toString() ?? 'Service AI gặp lỗi.');
      return;
    }
    if (message['type'] == 'ready') {
      setState(() {
        _ready = true;
        _protocol = (message['stream_protocol'] as num?)?.toInt() ?? 1;
        _liveObservations = message['live_glyph_observations'] == true;
        _liveWordObservations = message['live_word_observations'] == true;
        _classes = (message['word_classes'] as num?)?.toInt() ?? 0;
        _wordEngine = message['word_engine']?.toString() ?? '';
        _embeddingWeight =
            ((message['word_policy'] as Map?)?['embed_weight'] as num?)
                ?.toDouble() ??
            0;
      });
      return;
    }
    if (message['type'] == 'frame_received') {
      if ((message['sequence'] as num?)?.toInt() == _sequence - 1) {
        _pending = false;
      }
      return;
    }
    if (message['type'] == 'observation_received') {
      if (message['timestamp_ms'] == _pendingObservation) {
        _pendingObservation = null;
        final waiting = _waitingObservation;
        _waitingObservation = null;
        if (waiting != null) _sendObservation(waiting);
      }
      return;
    }
    if (message['type'] != 'result') return;
    final camera = _camera;
    final anchor = message['foreground_context'];
    if (camera is ForegroundTrackingCamera && anchor is List) {
      (camera as ForegroundTrackingCamera).updateTrackingContext(
        anchor,
        (message['timestamp_ms'] as num).round(),
      );
    }
    if (_protocol < 2) _pending = false;
    _lastResult = _clock.elapsedMilliseconds;
    _streamTiming.received((message['sequence'] as num?)?.toInt(), _lastResult);
    String? spoken;
    for (final event in message['events'] as List? ?? []) {
      final id = ((event as Map)['id'] as num?)?.toInt() ?? 0;
      if (id > _lastEvent) {
        _lastEvent = id;
        spoken = event['label']?.toString();
      }
    }
    void updateUi() {
      _landmarks = message['landmarks'] as List? ?? [];
      _opencv = message['opencv'] as Map<String, dynamic>? ?? {};
      _inference = message['inference'] as Map<String, dynamic>? ?? {};
      _confirmed = message['confirmed'] as String?;
      _hands = (message['hands'] as num?)?.toInt() ?? 0;
      _processingMs = (message['processing_ms'] as num?)?.toDouble() ?? 0;
      _fps = (message['detection_fps'] as num?)?.toDouble() ?? 0;
      _dropped = (message['dropped_frames'] as num?)?.toInt() ?? 0;
      _status = message['status']?.toString() ?? 'tracking';
      _landmarkSource = message['landmark_source']?.toString() ?? 'cpu';
    }

    // Joints use their own notifier. Do not rebuild the whole screen for every
    // service frame; status/confirmed-word transitions still appear immediately.
    final changed =
        message['confirmed'] != _confirmed ||
        (message['status']?.toString() ?? 'tracking') != _status ||
        ((message['hands'] as num?)?.toInt() ?? 0) != _hands;
    if (!_localTrackingActive ||
        changed ||
        spoken != null ||
        _lastResult - _lastUiUpdate >= 125) {
      _lastUiUpdate = _lastResult;
      setState(updateUi);
    } else {
      updateUi();
    }
    if (_autoSpeak && spoken != null) unawaited(_speak(spoken));
  }

  Future<void> _toggleDiagnostic() async {
    if (!widget.diagnosticsEnabled ||
        _starting ||
        _opening ||
        _diagnosticBusy) {
      return;
    }
    if (!_diagnostic.recording && _diagnostic.messages.isEmpty) {
      _diagnostic.start();
      _diagnostic.add({
        'kind': 'session_start',
        'mode': _mode,
        'client_started_ms': _clock.elapsedMilliseconds,
        'observation_pacing': _phaseObservationPacing && _mode == 'words'
            ? 'phase_15hz_v1'
            : 'minimum_gap_66ms',
      });
      // A fresh connection requests the existing worker journal and identity.
      await _start();
      return;
    }
    setState(() => _diagnosticBusy = true);
    _diagnostic.add({
      'kind': 'session_stop',
      'client_stopped_ms': _clock.elapsedMilliseconds,
      'last_frame_sequence': _sequence - 1,
      'frame_awaiting_receipt': _pending,
      'observation_awaiting_receipt': _pendingObservation,
    });
    _diagnostic.recording = false;
    try {
      await _stop();
      final message = await widget.diagnosticExporter(_diagnostic.export());
      _diagnostic.clear();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa xuất được chẩn đoán. Bấm xuất để thử lại.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _diagnosticBusy = false);
    }
  }

  Future<void> _speak(String text) async {
    try {
      final state = AppScope.of(context);
      await _speech.speak(
        text,
        speed: state.speechSpeed,
        pitch: state.speechPitch,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chưa phát được giọng nói tiếng Việt trên thiết bị này.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _settings() async {
    final controller = TextEditingController(text: _url);
    var mode = _mode, overlays = _showOpenCv, speak = _autoSpeak;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cài đặt nhận diện',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ service AI',
                    labelStyle: TextStyle(color: _muted),
                    fillColor: _ink,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  dropdownColor: _card,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Chế độ',
                    labelStyle: TextStyle(color: _muted),
                    fillColor: _ink,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'words',
                      child: Text('Từ / cụm từ'),
                    ),
                    DropdownMenuItem(value: 'letters', child: Text('Chữ cái')),
                    DropdownMenuItem(value: 'digits', child: Text('Chữ số')),
                    DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                  ],
                  onChanged: (value) => update(() => mode = value ?? mode),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _blue,
                  title: const Text(
                    'Hiện phân tích OpenCV',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'OpenCV vẫn xử lý chuyển động khi ẩn lớp vẽ.',
                    style: TextStyle(color: _muted),
                  ),
                  value: overlays,
                  onChanged: (v) => update(() => overlays = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _blue,
                  title: const Text(
                    'Tự đọc kết quả',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: speak,
                  onChanged: (v) => update(() => speak = v),
                ),
                Text(
                  '$_hands tay · ${_fps.toStringAsFixed(1)} FPS dò tay · ${_processingMs.round()} ms xử lý AI\n'
                  '${_streamTiming.sendFps.toStringAsFixed(1)} ảnh/giây gửi đi · ${_streamTiming.encodeMs.round()} ms mã hóa ảnh\n'
                  '${_streamTiming.resultMs == null ? "Chưa có" : _streamTiming.resultMs.toString()} ms gửi → kết quả (gồm hàng chờ và xử lý)\n'
                  '$_classes từ trong model · $_dropped khung cũ được bỏ qua',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                if (_inference.isNotEmpty)
                  Text(
                    '${_inference["inference_ms"] ?? "—"} ms nhận diện chuỗi · '
                    '${_inference["observation_overruns"] ?? 0} quan sát bị quá tải',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                if (_wordEngine.isNotEmpty)
                  Text(
                    'Bộ nhận diện từ: ${_wordEngine.toUpperCase()} · '
                    'trọng số embedding ${(_embeddingWeight * 100).round()}%',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                Text(
                  (_landmarkSource == 'browser_gpu' ||
                          _landmarkSource == 'android_gpu')
                      ? 'AI dùng landmark GPU cùng khung hình'
                      : 'AI dùng landmark CPU (dự phòng)',
                  style: const TextStyle(color: _muted),
                ),
                ValueListenableBuilder<LocalHandObservation?>(
                  valueListenable: _localHands,
                  builder: (_, observation, _) => Text(
                    observation?.captureSource == 'initializing'
                        ? 'Đang khởi tạo bộ dò tay tại thiết bị…'
                        : observation == null
                        ? 'Landmark từ service AI.'
                        : '${observation.fps.toStringAsFixed(1)} FPS landmark tại thiết bị · ${observation.processingMs.round()} ms. '
                              '${observation.captureSource.startsWith("android_")
                                  ? "MediaPipe Android ${observation.captureSource.substring(8).toUpperCase()}."
                                  : observation.captureSource == "track_processor"
                                  ? "Luồng camera trực tiếp."
                                  : "Luồng ảnh từ video."} '
                              'Model Colab xác nhận ký hiệu. '
                              '${observation.captureAgeMs == null ? "" : "Ảnh → mốc tay ${observation.captureAgeMs!.round()} ms. "}'
                              '${observation.initializationMs == null ? "" : "Khởi tạo ${(observation.initializationMs! / 1000).toStringAsFixed(1)} s."}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Lưu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final value = controller.text.trim();
    controller.dispose();
    if (!mounted || saved != true) return;
    try {
      SignAiConfig.socketUri(value);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    final reconnect = _camera != null && (mode != _mode || value != _url);
    setState(() {
      _mode = mode;
      _showOpenCv = overlays;
      _autoSpeak = speak;
      _url = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sign_ai_service_url', value);
    await prefs.setString('sign_ai_mode', mode);
    if (reconnect && mounted) await _start();
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nhận diện ký hiệu'),
      content: const Text(
        'Giữ mặt và cả hai tay trong khung hình, đủ sáng. Thực hiện trọn ký hiệu rồi nghỉ nhẹ. Kết quả chỉ xuất hiện khi vượt qua các bước kiểm tra; điểm model không phải độ chính xác đã kiểm định. Model Colab nhận diện trực tiếp; LM Studio không tham gia nhận diện camera.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );

  void _permissionHelp() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cấp quyền camera'),
      content: const Text(
        '1. Mở app bằng http://localhost:8080 hoặc HTTPS.\n2. Bấm Cho phép camera, rồi chọn Cho phép trong thông báo của trình duyệt.\n3. Nếu từng chọn Chặn: mở biểu tượng bên trái thanh địa chỉ → Cài đặt trang web → Camera → Cho phép, tải lại trang.\n4. Kiểm tra Cài đặt Windows → Quyền riêng tư và bảo mật → Camera nếu thiết bị vẫn bị chặn.\n\nĐọc kết quả thành tiếng không cần quyền microphone. Microphone chỉ được xin khi bạn chọn Giọng nói → Văn bản.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đã hiểu'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _watchdog?.cancel();
    _localStale?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_localSubscription?.cancel());
    _localHands.dispose();
    unawaited(_channel?.sink.close());
    unawaited(_camera?.close());
    unawaited(_speech.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_consent) {
      return DevicePermissionPage(
        camera: true,
        onSettings: _settings,
        onAllow: () {
          setState(() => _consent = true);
          unawaited(_start());
        },
      );
    }
    final success = _confirmed != null;
    final lost =
        _ready &&
        _camera != null &&
        !_opening &&
        _status != 'connecting' &&
        _hands == 0 &&
        (_localHands.value?.landmarks.isEmpty ?? true);
    final unclear =
        _error != null ||
        lost ||
        _status == 'uncertain' ||
        _status == 'vision_unavailable';
    final color = success
        ? _green
        : unclear
        ? _red
        : Colors.transparent;
    final waiting = _status == 'connecting'
        ? 'Camera đã mở. Đang kết nối AI…'
        : _status == 'idle'
        ? 'Cho phép camera để bắt đầu'
        : _status == 'verifying'
        ? 'Đang đối chiếu ký hiệu…'
        : 'Kết quả sẽ hiển thị ở đây…';
    final detail =
        _error ??
        (_status == 'vision_unavailable'
            ? 'Chưa đối chiếu được ảnh. Kiểm tra LM Studio hoặc mẫu ký hiệu.'
            : lost
            ? 'Đưa một hoặc hai tay vào khung hình'
            : _mode == 'digits'
            ? 'Chế độ chữ số · model trực tiếp. Đưa tay rõ trong khung hình.'
            : _mode == 'letters'
            ? 'Chế độ chữ cái · model trực tiếp. Đưa tay rõ trong khung hình.'
            : _status == 'verifying'
            ? 'Model đã có ứng viên. Đang chờ LM Studio đối chiếu ảnh.'
            : _status == 'uncertain'
            ? 'Model và LM Studio chưa thống nhất ký hiệu. Hãy thử lại.'
            : 'Model Colab trực tiếp · Giữ mặt và cả hai tay trong khung hình');
    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => backOrHome(context),
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
        ),
        title: const Text(
          'Nhận diện ký hiệu',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        actions: [
          if (widget.diagnosticsEnabled)
            IconButton(
              onPressed: _opening || _diagnosticBusy ? null : _toggleDiagnostic,
              tooltip: _diagnostic.recording || _diagnostic.messages.isNotEmpty
                  ? 'Dừng và xuất chẩn đoán'
                  : 'Ghi chẩn đoán (không ảnh)',
              icon: Icon(
                _diagnostic.recording || _diagnostic.messages.isNotEmpty
                    ? Icons.download
                    : Icons.bug_report_outlined,
                color: _diagnostic.recording ? _red : null,
              ),
            ),
          IconButton(
            onPressed: _help,
            tooltip: 'Hướng dẫn',
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            onPressed: _opening ? null : _settings,
            tooltip: 'Cài đặt nhận diện',
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: color, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_camera != null && _cameraReady)
                      Center(
                        child: AspectRatio(
                          aspectRatio: _camera!.aspectRatio,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _camera!.preview(),
                              if (_showOpenCv)
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: OpenCvOverlayPainter(
                                      _opencv,
                                      mirror: _front,
                                    ),
                                  ),
                                ),
                              IgnorePointer(
                                child:
                                    ValueListenableBuilder<
                                      LocalHandObservation?
                                    >(
                                      valueListenable: _localHands,
                                      builder: (_, observation, _) =>
                                          CustomPaint(
                                            key: const ValueKey(
                                              'sign-hand-landmarks',
                                            ),
                                            painter: _HandPainter(
                                              observation?.captureSource ==
                                                      'initializing'
                                                  ? _landmarks
                                                  : observation?.landmarks ??
                                                        (_localTrackingActive
                                                            ? const []
                                                            : _landmarks),
                                              mirror: _front,
                                            ),
                                          ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: CustomPaint(
                          painter: _GuidePainter(),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_opening)
                                  const CircularProgressIndicator(color: _blue)
                                else
                                  const Icon(
                                    Icons.pan_tool_outlined,
                                    size: 58,
                                    color: _muted,
                                  ),
                                const SizedBox(height: 22),
                                Text(
                                  _opening
                                      ? 'Đang chờ quyền camera…'
                                      : 'Cho phép camera để bắt đầu',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (success || unclear || _status == 'verifying')
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 64,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: success
                                  ? _green
                                  : unclear
                                  ? _red
                                  : _card,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              success
                                  ? '●  Nhận diện thành công'
                                  : _error != null
                                  ? (_cameraError
                                        ? 'Chưa mở được camera'
                                        : 'Chưa kết nối AI')
                                  : lost
                                  ? 'Không thấy tay'
                                  : unclear
                                  ? 'Chưa nhận diện rõ'
                                  : 'Đang đối chiếu ảnh',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: ValueListenableBuilder<LocalHandObservation?>(
                        valueListenable: _localHands,
                        builder: (_, observation, _) =>
                            observation?.captureSource == 'initializing'
                            ? const Card(
                                color: Color(0xDD202938),
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Đang khởi tạo bộ dò tay…',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton(
                        onPressed: _opening
                            ? null
                            : () {
                                setState(() => _front = !_front);
                                if (_camera != null) unawaited(_start());
                              },
                        tooltip: 'Đổi camera',
                        icon: const Icon(
                          Icons.flip_camera_ios_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .42,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF101010),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RecognitionResultCard(
                      label: _confirmed,
                      waiting: waiting,
                      detail: detail,
                      unclear: unclear,
                      vision: false,
                      errorTitle: _error == null
                          ? null
                          : (_cameraError
                                ? 'Chưa mở được camera'
                                : 'Chưa kết nối AI'),
                    ),
                    if (_cameraError)
                      TextButton.icon(
                        onPressed: _permissionHelp,
                        icon: const Icon(Icons.lock_open, color: _muted),
                        label: const Text(
                          'Hướng dẫn cấp quyền',
                          style: TextStyle(color: _muted),
                        ),
                      ),
                    const SizedBox(height: 18),
                    if (success)
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 17,
                                ),
                              ),
                              onPressed: () {
                                AppScope.of(context).addWord(_confirmed!);
                                openRoot(context, 'S13');
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm vào câu'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _speak(_confirmed!),
                            tooltip: 'Đọc tiếng Việt',
                            color: Colors.white,
                            icon: const Icon(Icons.volume_up_outlined),
                          ),
                          IconButton(
                            onPressed: _start,
                            tooltip: 'Thử lại',
                            color: const Color(0xFF889AFF),
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              onPressed: _opening ? null : _start,
                              icon: Icon(
                                _camera == null
                                    ? Icons.videocam_outlined
                                    : Icons.refresh,
                              ),
                              label: Text(
                                _camera == null && _error == null
                                    ? 'Cho phép camera'
                                    : 'Thử lại',
                              ),
                            ),
                          ),
                          if (unclear) ...[
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () => openRoot(context, 'S22'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF889AFF),
                              ),
                              child: const Text('Từ điển'),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecognitionResultCard extends StatelessWidget {
  const RecognitionResultCard({
    super.key,
    this.label,
    required this.waiting,
    required this.detail,
    required this.unclear,
    required this.vision,
    this.errorTitle,
  });
  final String? label;
  final String waiting, detail;
  final bool unclear, vision;
  final String? errorTitle;
  @override
  Widget build(BuildContext context) {
    final success = label != null;
    final tone = success
        ? _green
        : unclear
        ? _red
        : _muted;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: success
            ? const Color(0xFF19251D)
            : unclear
            ? const Color(0xFF2A2020)
            : const Color(0xFF202020),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tone.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (success) ...[
            Text(
              vision ? 'Model + đối chiếu ảnh' : 'Đã nhận diện',
              style: TextStyle(color: tone, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              label!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else ...[
            Text(
              unclear ? (errorTitle ?? 'Chưa nhận diện rõ') : waiting,
              style: TextStyle(
                color: tone,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            if (unclear) ...[
              const SizedBox(height: 8),
              Text(detail, style: const TextStyle(color: _muted, height: 1.4)),
            ],
          ],
        ],
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(20)),
      );
    final paint = Paint()
      ..color = const Color(0xFF475364)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 14) {
        canvas.drawPath(
          metric.extractPath(offset, (offset + 7).clamp(0, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) => false;
}

class OpenCvOverlayPainter extends CustomPainter {
  OpenCvOverlayPainter(this.analysis, {required this.mirror});
  final Map<String, dynamic> analysis;
  final bool mirror;

  Offset point(List<dynamic> xy, Size size) {
    final x = (xy[0] as num).toDouble();
    return Offset(
      (mirror ? 1 - x : x) * size.width,
      (xy[1] as num).toDouble() * size.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final regionPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final flowPaint = Paint()
      ..color = Colors.amberAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final value in analysis['regions'] as List? ?? []) {
      final region = value as Map;
      final box = region['box'] as List;
      final x = (box[0] as num).toDouble(), y = (box[1] as num).toDouble();
      final w = (box[2] as num).toDouble(), h = (box[3] as num).toDouble();
      final a = point([x, y], size), b = point([x + w, y + h], size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(a, b),
          const Radius.circular(6),
        ),
        regionPaint,
      );
      final hull = region['hull'] as List;
      if (hull.length >= 3) {
        final first = point(hull.first as List, size);
        final path = Path()..moveTo(first.dx, first.dy);
        for (final p in hull.skip(1)) {
          final next = point(p as List, size);
          path.lineTo(next.dx, next.dy);
        }
        path.close();
        canvas.drawPath(path, regionPaint);
      }
    }
    for (final vector in analysis['flow_vectors'] as List? ?? []) {
      final ends = vector as List;
      final a = point(ends[0] as List, size), b = point(ends[1] as List, size);
      final delta = b - a;
      if (delta.distance < .5) {
        continue;
      }
      canvas.drawLine(a, b, flowPaint);
      final unit = delta / delta.distance;
      final normal = Offset(-unit.dy, unit.dx);
      canvas.drawLine(b, b - unit * 6 + normal * 3, flowPaint);
      canvas.drawLine(b, b - unit * 6 - normal * 3, flowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant OpenCvOverlayPainter old) =>
      analysis != old.analysis || mirror != old.mirror;
}

class _HandPainter extends CustomPainter {
  _HandPainter(this.hands, {required this.mirror});
  final List<dynamic> hands;
  final bool mirror;
  static const edges = [
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
    (0, 5),
    (5, 6),
    (6, 7),
    (7, 8),
    (5, 9),
    (9, 10),
    (10, 11),
    (11, 12),
    (9, 13),
    (13, 14),
    (14, 15),
    (15, 16),
    (13, 17),
    (0, 17),
    (17, 18),
    (18, 19),
    (19, 20),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.lightGreenAccent
      ..strokeWidth = 2;
    for (final hand in hands) {
      final points = (hand as List).map((p) {
        final xy = p as List;
        final x = (xy[0] as num).toDouble();
        return Offset(
          (mirror ? 1 - x : x) * size.width,
          (xy[1] as num).toDouble() * size.height,
        );
      }).toList();
      if (points.length != 21) {
        continue;
      }
      for (final (a, b) in edges) {
        canvas.drawLine(points[a], points[b], line);
      }
      for (final p in points) {
        canvas.drawCircle(p, 3, line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HandPainter old) =>
      hands != old.hands || mirror != old.mirror;
}
