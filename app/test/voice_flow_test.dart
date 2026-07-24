import 'dart:typed_data';

import 'package:dayby/api/api_client.dart';
import 'package:dayby/lang.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:dayby/screens/log_screen.dart';
import 'package:dayby/voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A microphone that never touches one.
class _FakeVoice extends VoiceRecorder {
  int opened = 0;
  VoidCallback? _onEnd;

  @override
  Future<bool> isSupported() async => true;

  /// Asking iOS for the microphone is not instant. That gap is the whole bug: nothing on
  /// screen has changed yet, so the caregiver taps again. A fake that answers immediately
  /// closes the gap and tests nothing.
  @override
  Future<bool> hasPermission() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return true;
  }

  @override
  Future<void> start({required VoidCallback onEnd}) async {
    opened++;
    _onEnd = onEnd;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<Uint8List?> stop() async => Uint8List.fromList([0, 1, 2]);

  @override
  Future<void> dispose() async {}

  /// The caregiver stops talking and the silence detector calls time.
  void stopsTalking() => _onEnd?.call();
}

class _FakeApiClient extends ApiClient {
  List<Turn>? sentHistory;
  List<String>? sentLanguages;

  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')];

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async => const [];

  @override
  Future<IngestVoiceResult> ingestVoice({
    required Uint8List bytes,
    required String mimeType,
    List<Turn> history = const [],
    List<String> languages = const [],
    String? recordLang,
  }) async {
    sentHistory = history;
    sentLanguages = languages;
    return const IngestVoiceResult(
      transcript: 'formula 120ml',
      result: StructuredResult(
        action: 'create',
        events: [
          StructuredEvent(
            type: 'feeding',
            subtype: 'formula',
            fields: {'amount_ml': 120},
          ),
        ],
        reply: 'Formula, 120 ml. Save it?',
      ),
    );
  }
}

Future<(_FakeVoice, _FakeApiClient)> _openChat(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  final voice = _FakeVoice();
  final api = _FakeApiClient();

  // The chat opened straight, so the mic starts idle: these exercise the manual
  // tap-to-record mechanics. (Opening it from the orb auto-starts; that path is covered
  // by action_button_test.)
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(api),
        voiceRecorderProvider.overrideWithValue(voice),
      ],
      child: const MaterialApp(home: LogScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return (voice, api);
}

final _mic = find.widgetWithIcon(FilledButton, Icons.mic);

void main() {
  testWidgets('an impatient second tap does not open a second recording',
      (tester) async {
    final (voice, _) = await _openChat(tester);

    // Asking for the microphone and opening it both take a moment, and nothing on screen
    // has changed yet, so of course they tap again. On a real iPhone this ran two
    // recordings at once: every sample arrived twice, and the first one's 30-second
    // backstop was left armed, waiting to cut off whatever was being said 30s later.
    await tester.tap(_mic);
    await tester.tap(_mic);
    await tester.pumpAndSettle();

    expect(voice.opened, 1);
  });

  testWidgets('what the server heard is what appears as the message you sent',
      (tester) async {
    final (voice, _) = await _openChat(tester);

    await tester.tap(_mic);
    await tester.pumpAndSettle();

    voice.stopsTalking();
    await tester.pumpAndSettle();

    // Nothing is shown while they speak — the server does the listening — so the
    // transcript is the first sight they get of the words it understood.
    expect(find.text('formula 120ml'), findsOneWidget);
    expect(find.text('Formula, 120 ml. Save it?'), findsOneWidget);
    expect(find.text('Feeding · formula · 120 ml'), findsOneWidget);
  });

  testWidgets('a spoken follow-up carries the conversation too', (tester) async {
    final (voice, api) = await _openChat(tester);

    await tester.tap(_mic);
    await tester.pumpAndSettle();
    voice.stopsTalking();
    await tester.pumpAndSettle();

    await tester.tap(_mic);
    await tester.pumpAndSettle();
    voice.stopsTalking();
    await tester.pumpAndSettle();

    expect(
      [for (final t in api.sentHistory!) t.text],
      ['formula 120ml', 'Formula, 120 ml. Save it?'],
    );
  });

  testWidgets('the recording goes up with the languages this person speaks',
      (tester) async {
    final (voice, api) = await _openChat(tester);

    await tester.tap(_mic);
    await tester.pumpAndSettle();
    voice.stopsTalking();
    await tester.pumpAndSettle();

    // Without these the transcriber is guessing from the sound alone, and a Korean
    // sentence said over a crying baby comes back as Chinese.
    expect(api.sentLanguages, kDefaultLanguages);
  });
}
