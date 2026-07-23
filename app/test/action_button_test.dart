import 'dart:typed_data';

import 'package:dayby/api/api_client.dart';
import 'package:dayby/intent_bridge.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:dayby/screens/log_screen.dart';
import 'package:dayby/voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the iOS App Intent. Hands over its action once, then nothing -- reading
/// clears it on the real side too.
class _FakeIntentBridge extends IntentBridge {
  _FakeIntentBridge(this._action);

  String? _action;

  @override
  Future<String?> takePendingAction() async {
    final action = _action;
    _action = null;
    return action;
  }
}

class _FakeVoice extends VoiceRecorder {
  int opened = 0;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start({required VoidCallback onEnd}) async => opened++;

  @override
  Future<Uint8List?> stop() async => Uint8List.fromList([0, 1, 2]);

  @override
  Future<void> dispose() async {}
}

class _FakeApiClient extends ApiClient {
  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')];

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    int limit = 100,
  }) async => const [];
}

Future<_FakeVoice> _launch(WidgetTester tester, {required String? action}) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  final voice = _FakeVoice();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(_FakeApiClient()),
        voiceRecorderProvider.overrideWithValue(voice),
        intentBridgeProvider.overrideWithValue(_FakeIntentBridge(action)),
      ],
      child: const DaybyApp(),
    ),
  );
  await tester.pumpAndSettle();
  return voice;
}

void main() {
  testWidgets('the Action button opens the app already listening', (tester) async {
    final voice = await _launch(tester, action: 'log_voice');

    // No tap: the voice chat came up on its own and the mic opened.
    expect(find.byType(LogScreen), findsOneWidget);
    expect(voice.opened, 1);
  });

  testWidgets('an ordinary launch stays on Home with the mic shut', (tester) async {
    final voice = await _launch(tester, action: null);

    expect(find.byType(LogScreen), findsNothing);
    expect(voice.opened, 0);
  });
}
