import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';

class SpeechOutput {
  final FlutterTts _tts = FlutterTts();
  Future<void> speak(String text, {double speed = 1, double pitch = 1}) async {
    if (text.trim().isEmpty) {
      return;
    }
    await _tts.stop();
    final supported = await _tts.isLanguageAvailable('vi-VN');
    if (supported == false) {
      throw StateError(
        'Thiết bị chưa có giọng tiếng Việt. Hãy cài giọng vi-VN trong cài đặt đọc văn bản.',
      );
    }
    await _tts.setLanguage('vi-VN');
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate((speed * 0.5).clamp(0.1, 1.0));
    await _tts.setPitch(pitch.clamp(0.5, 2.0));
    await _tts.speak(text);
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } on MissingPluginException {
      /* No active voice engine to stop on this platform. */
    }
  }
}
