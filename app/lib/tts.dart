import 'package:flutter_tts/flutter_tts.dart';

/// Speaks the LLM's reply out loud. Guarded: where TTS isn't available
/// (unsupported browser, tests) it silently does nothing — the reply is still
/// shown in the chat.
class Tts {
  final FlutterTts _tts = FlutterTts();

  Future<void> speak(String text, {String lang = 'ko'}) async {
    if (text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(lang == 'ko' ? 'ko-KR' : 'en-US');
      await _tts.speak(text);
    } catch (_) {
      // No voice here; the text still appears on screen.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
