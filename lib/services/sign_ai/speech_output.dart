import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class SpeechOutputException implements Exception {
  const SpeechOutputException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MissingVietnameseVoiceException extends SpeechOutputException {
  const MissingVietnameseVoiceException()
    : super(
        'Thiết bị chưa có giọng tiếng Việt. Cài giọng Tiếng Việt trong cài đặt đọc văn bản, rồi quay lại bấm Phát.',
      );
}

class SpeechOutput {
  final FlutterTts _tts = FlutterTts();
  int _generation = 0;
  bool get canOpenVoiceSettings =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _selectVietnamese() async {
    for (final language in ['vi-VN', 'vi']) {
      if (await _tts.isLanguageAvailable(language) == true &&
          await _tts.setLanguage(language) == 1) {
        return;
      }
    }
    // Some engines expose a named Vietnamese voice but reject the locale probe.
    final voices = await _tts.getVoices;
    if (voices is List) {
      for (final voice in voices.whereType<Map>()) {
        final locale = '${voice['locale'] ?? ''}';
        final language = locale.replaceAll('_', '-').toLowerCase();
        final name = '${voice['name'] ?? ''}';
        if ((language == 'vi' || language.startsWith('vi-')) &&
            name.isNotEmpty &&
            voice['notInstalled'] != true) {
          await _tts.setLanguage(locale);
          if (await _tts.setVoice({'name': name, 'locale': locale}) == 1) {
            return;
          }
        }
      }
    }
    throw const MissingVietnameseVoiceException();
  }

  Future<bool> openVoiceSettings() async {
    if (!canOpenVoiceSettings) return false;
    try {
      return await const MethodChannel('signvoice/speech')
              .invokeMethod<bool>('openVoiceSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> speak(String text, {double speed = 1, double pitch = 1}) async {
    if (text.trim().isEmpty) {
      return;
    }
    final generation = ++_generation;
    await _tts.stop();
    await _selectVietnamese();
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate((speed * 0.5).clamp(0.1, 1.0));
    await _tts.setPitch(pitch.clamp(0.5, 2.0));
    if (generation != _generation) return;
    final result = await _tts.speak(text);
    if (generation == _generation && result == 0) {
      throw const SpeechOutputException(
        'Không phát được giọng nói. Kiểm tra âm lượng và giọng tiếng Việt rồi thử lại.',
      );
    }
  }

  Future<void> stop() async {
    _generation++;
    try {
      await _tts.stop();
    } on MissingPluginException {
      /* No active voice engine to stop on this platform. */
    }
  }
}
