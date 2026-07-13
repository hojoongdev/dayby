import 'package:dayby/voice.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two real rooms, in dBFS. The office floor is what an iPhone 15 Pro actually measured;
/// the quiet one is what a bedroom at night looks like. A single hardcoded threshold
/// cannot serve both, which is why the detector measures the room instead.
const officeFloor = -29.0;
const quietFloor = -50.0;

/// Someone talking into a phone they are holding.
const speech = -15.0;

void main() {
  final start = DateTime(2026, 7, 13, 21, 0);
  DateTime at(int ms) => start.add(Duration(milliseconds: ms));

  /// Feed the room's own noise for as long as the detector spends measuring it.
  void calibrate(SilenceDetector detector, double floor) {
    for (var ms = 0; ms <= 600; ms += 150) {
      expect(detector.ended(floor, at(ms)), isFalse);
    }
  }

  test('the room sets the threshold, not a constant', () {
    final office = SilenceDetector();
    final bedroom = SilenceDetector();

    calibrate(office, officeFloor);
    calibrate(bedroom, quietFloor);

    expect(office.threshold, closeTo(-19, 0.01));
    expect(bedroom.threshold, closeTo(-40, 0.01));
  });

  test('a noisy room does not swallow the end of the sentence', () {
    // The bug this replaced: a fixed -35 threshold sits *below* an office floor of -29,
    // so every sample read as speech and the recording never ended on its own.
    final detector = SilenceDetector();
    calibrate(detector, officeFloor);

    expect(detector.ended(speech, at(750)), isFalse);
    expect(detector.ended(officeFloor, at(900)), isFalse);
    expect(detector.ended(officeFloor, at(2500)), isTrue);
  });

  test('silence before the first word does not end the recording', () {
    final detector = SilenceDetector();

    // They tapped the mic and are still working out what to say. Ending here would make
    // the button useless: it would hang up before anyone spoke.
    for (var ms = 0; ms < 8000; ms += 150) {
      expect(
        detector.ended(quietFloor, at(ms)),
        isFalse,
        reason: 'ended after ${ms}ms of not having spoken yet',
      );
    }
  });

  test('a sentence, then quiet, ends the recording', () {
    final detector = SilenceDetector();
    calibrate(detector, quietFloor);

    expect(detector.ended(speech, at(750)), isFalse);
    expect(detector.ended(quietFloor, at(900)), isFalse);
    expect(detector.ended(quietFloor, at(1600)), isFalse);
    // 1.5s of quiet since the last word.
    expect(detector.ended(quietFloor, at(2500)), isTrue);
  });

  test('drawing breath mid-sentence does not end it', () {
    final detector = SilenceDetector();
    calibrate(detector, quietFloor);

    expect(detector.ended(speech, at(750)), isFalse);
    // A pause, but not a long one, and then they carry on.
    expect(detector.ended(quietFloor, at(1400)), isFalse);
    expect(detector.ended(speech, at(1700)), isFalse);

    // The breath does not count towards the 1.5 seconds: the clock starts again at the
    // quiet that follows the last word, so a stop-start sentence is not cut in half.
    expect(detector.ended(quietFloor, at(1850)), isFalse);
    expect(detector.ended(quietFloor, at(3000)), isFalse);
    expect(detector.ended(quietFloor, at(3400)), isTrue);
  });

  test('a room that never falls quiet never ends it', () {
    final detector = SilenceDetector();
    calibrate(detector, quietFloor);

    for (var ms = 750; ms < 10000; ms += 150) {
      expect(detector.ended(speech, at(ms)), isFalse);
    }
    // Which is what VoiceRecorder.maxLength is for.
    expect(VoiceRecorder.maxLength, const Duration(seconds: 30));
  });

  test('a room misjudged as loud runs on rather than cutting them off', () {
    // If the caregiver starts talking during calibration, the room reads as loud and the
    // threshold lands above their voice. The recording then never ends by itself and they
    // tap stop -- exactly what they did before. It must never end early instead.
    final detector = SilenceDetector();
    for (var ms = 0; ms <= 600; ms += 150) {
      expect(detector.ended(speech, at(ms)), isFalse);
    }

    for (var ms = 750; ms < 8000; ms += 150) {
      expect(detector.ended(quietFloor, at(ms)), isFalse, reason: 'cut them off at ${ms}ms');
    }
  });
}
