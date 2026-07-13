import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Decides when a sentence has ended.
///
/// On-device STT stopped itself (`pauseFor`), and that is what let a caregiver log a feed
/// with one hand while holding the baby. The server transcribes now, so the end of the
/// sentence has to be found here.
///
/// There is no good fixed level to compare against: a real iPhone in a real room read a
/// noise floor of -29 dBFS, where a quiet bedroom sits nearer -50. Anything hardcoded is
/// wrong in one of those rooms. So the room is measured at the top of every recording, and
/// speech is whatever rises clearly above whatever that room turned out to be.
class SilenceDetector {
  SilenceDetector({
    this.margin = 10,
    this.silenceFor = const Duration(milliseconds: 1500),
    this.calibrateFor = const Duration(milliseconds: 600),
  });

  /// How far above the room's own noise, in dB, a sound has to be to be a voice.
  final double margin;

  /// How long the quiet has to hold. Long enough to draw breath mid-sentence.
  final Duration silenceFor;

  /// Nobody speaks the instant they tap the button, so the opening moment is the room.
  final Duration calibrateFor;

  final List<double> _room = [];
  DateTime? _opened;
  double? _threshold;
  bool _heardSpeech = false;
  DateTime? _quietSince;

  /// The level a sound has to beat to count as speech, once the room has been measured.
  double? get threshold => _threshold;

  /// True once they have spoken and then stopped.
  bool ended(double db, DateTime at) {
    _opened ??= at;

    if (_threshold == null) {
      _room.add(db);
      if (at.difference(_opened!) < calibrateFor) return false;
      // The median, so one slammed door does not become the room.
      _threshold = _median(_room) + margin;
    }

    if (db >= _threshold!) {
      _heardSpeech = true;
      _quietSince = null;
      return false;
    }
    // Quiet before the first word is someone deciding what to say, not the end of it.
    // It also means a misjudged room can only fail one way: the recording runs on and
    // they tap stop, which is what they would have done anyway. It never cuts them off.
    if (!_heardSpeech) return false;
    _quietSince ??= at;
    return at.difference(_quietSince!) >= silenceFor;
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }
}

/// Records a sentence and stops when the caregiver does, then hands over the audio for
/// the server to transcribe.
class VoiceRecorder {
  VoiceRecorder({AudioRecorder? recorder}) : _rec = recorder ?? AudioRecorder();

  final AudioRecorder _rec;

  /// Nobody needs half a minute to say a nappy was wet. A backstop for a room too loud
  /// to ever fall under the threshold.
  static const maxLength = Duration(seconds: 30);

  static const mimeType = 'audio/wav';

  final _levels = StreamController<double>.broadcast();

  /// 0..1, so the button can show that the mic is hearing something and is not dead.
  Stream<double> get level => _levels.stream;

  StreamSubscription<Amplitude>? _amplitudes;
  Timer? _tooLong;
  SilenceDetector _silence = SilenceDetector();
  bool _finished = false;

  Future<bool> isSupported() => _rec.isEncoderSupported(AudioEncoder.wav);

  Future<bool> hasPermission() => _rec.hasPermission();

  /// Starts listening. [onEnd] fires once, when they stop talking or when they have been
  /// talking for [maxLength]. The caller then calls [stop] for the recording.
  Future<void> start({required VoidCallback onEnd}) async {
    _silence = SilenceDetector();
    _finished = false;

    void finish() {
      if (_finished) return;
      _finished = true;
      onEnd();
    }

    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: await _scratchFile(),
    );

    _amplitudes =
        _rec.onAmplitudeChanged(const Duration(milliseconds: 150)).listen((amp) {
      if (!_levels.isClosed) {
        _levels.add(((amp.current + 60) / 60).clamp(0.0, 1.0));
      }
      if (_silence.ended(amp.current, DateTime.now())) finish();
    });
    _tooLong = Timer(maxLength, finish);
  }

  /// The recording, or null if the mic gave us nothing.
  Future<Uint8List?> stop() async {
    await _disarm();
    final path = await _rec.stop();
    if (path == null) return null;
    final bytes = await XFile(path).readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }

  Future<void> cancel() async {
    await _disarm();
    await _rec.cancel();
  }

  Future<void> dispose() async {
    await _disarm();
    await _levels.close();
    await _rec.dispose();
  }

  Future<void> _disarm() async {
    _tooLong?.cancel();
    _tooLong = null;
    await _amplitudes?.cancel();
    _amplitudes = null;
  }

  /// One file, overwritten each time. On web this is ignored: stop() hands back a blob
  /// url instead, which XFile reads just the same.
  Future<String> _scratchFile() async {
    if (kIsWeb) return '';
    final dir = await getTemporaryDirectory();
    return '${dir.path}/dayby-speech.wav';
  }
}
