import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'media_access_error.dart';

abstract class SpeechInput extends ChangeNotifier {
  bool get busy;
  bool get listening;
  bool get permissionGranted;
  String get text;
  String? get error;
  Future<void> start();
  Future<void> stop();
  Future<void> cancel();
}

class DeviceSpeechInput extends SpeechInput {
  DeviceSpeechInput._();
  static final DeviceSpeechInput instance = DeviceSpeechInput._();
  final _speech = SpeechToText();
  bool _busy = false, _permission = false;
  String _text = '';
  String? _error;
  int _generation = 0;
  bool _requested = false;
  Completer<bool>? _startSignal;
  @override
  bool get busy => _busy;
  @override
  bool get listening => _speech.isListening;
  @override
  bool get permissionGranted => _permission;
  @override
  String get text => _text;
  @override
  String? get error => _error;

  @override
  Future<void> start() async {
    if (_busy || listening) return;
    final generation = ++_generation;
    final signal = Completer<bool>();
    _requested = true;
    _busy = true;
    _error = null;
    _text = '';
    notifyListeners();
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == SpeechToText.listeningStatus) {
            if (!_requested) {
              unawaited(_speech.cancel());
              return;
            }
            _permission = true;
            if (_startSignal?.isCompleted == false) {
              _startSignal!.complete(true);
            }
          } else if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            if (_startSignal?.isCompleted == false) {
              _startSignal!.complete(false);
            }
          }
          notifyListeners();
        },
        onError: (failure) {
          if (!_requested) return;
          if (_startSignal?.isCompleted == false) _startSignal!.complete(false);
          final code = failure.errorMsg;
          if (code.contains('permission') || code.contains('not-allowed')) {
            _permission = false;
            _error = mediaAccessError(
              'permission',
              device: 'microphone',
            ).message;
          } else if (code.contains('network')) {
            _error = 'Không kết nối được dịch vụ nhận dạng giọng nói. Kiểm tra Internet rồi thử lại.';
          } else if (code.contains('no_match') ||
              code.contains('speech_timeout') ||
              code.contains('no-speech')) {
            _error = 'Chưa nghe rõ lời nói. Bấm microphone để thử lại.';
          } else {
            _error =
                'Chưa nhận dạng được giọng nói ($code). Kiểm tra microphone và thử lại.';
          }
          notifyListeners();
        },
      );
      if (generation != _generation) return;
      if (!available) {
        _permission = false;
        _error ??= 'Chưa truy cập được microphone hoặc nhận dạng giọng nói chưa được hỗ trợ. Trên web hãy dùng Chrome/Edge, HTTPS hoặc localhost và cho phép microphone trong cài đặt trang web.';
        return;
      }
      _startSignal = signal;
      await _speech.listen(
        onResult: (result) {
          if (generation != _generation) return;
          _text = result.recognizedWords;
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          localeId: 'vi-VN',
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
      if (generation == _generation) await signal.future;
    } catch (failure) {
      if (generation == _generation) {
        _permission = false;
        _error = mediaAccessError(
          failure.toString(),
          device: 'microphone',
        ).message;
      }
    } finally {
      if (generation == _generation) {
        _busy = false;
        if (identical(_startSignal, signal)) _startSignal = null;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> stop() async {
    _requested = false;
    if (_startSignal?.isCompleted == false) _startSignal!.complete(false);
    await _speech.stop();
    notifyListeners();
  }

  @override
  Future<void> cancel() async {
    _requested = false;
    if (_startSignal?.isCompleted == false) _startSignal!.complete(false);
    _startSignal = null;
    _generation++;
    _busy = false;
    try {
      await _speech.cancel();
    } catch (_) {
      /* No active engine. */
    }
    notifyListeners();
  }
}
