import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks the LLM's reply out loud. Prefers a natural server voice (Gemini TTS) when one
/// is wired in, and falls back to on-device TTS otherwise -- so a reply is always spoken,
/// with or without a key. Guarded: where nothing can speak it silently does nothing and
/// the reply still shows in the chat.
class Tts {
  Tts({this.serverVoice});

  /// Fetches the reply as WAV audio, or null when the server has no voice. Injected so
  /// this class stays unaware of the API client.
  final Future<Uint8List?> Function(String text, String lang)? serverVoice;

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  Future<void> speak(String text, {String lang = 'ko'}) async {
    if (text.trim().isEmpty) return;
    await stop();
    if (serverVoice != null) {
      try {
        final audio = await serverVoice!(text, lang);
        if (audio != null && audio.isNotEmpty) {
          await _player.play(BytesSource(audio, mimeType: 'audio/wav'));
          return;
        }
      } catch (_) {
        // Fall through to the on-device voice.
      }
    }
    try {
      await _tts.setLanguage(lang == 'ko' ? 'ko-KR' : 'en-US');
      await _tts.speak(text);
    } catch (_) {
      // No voice here; the text still appears on screen.
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
