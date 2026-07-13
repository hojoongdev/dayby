import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.babies, this.result);

  final List<Baby> babies;
  final StructuredResult result;
  final List<Map<String, dynamic>> saved = [];

  @override
  Future<List<Baby>> listBabies() async => babies;

  @override
  Future<List<Event>> listEvents({String? babyId, String? type, int limit = 100}) async =>
      const [];

  @override
  Future<StructuredResult> ingestText(
    String text, {
    List<Turn> history = const [],
  }) async => result;

  @override
  Future<Event> createEvent({
    required String babyId,
    required String type,
    String? subtype,
    Map<String, dynamic> fields = const {},
    DateTime? time,
    String? note,
    String source = 'text',
    String? rawText,
  }) async {
    saved.add({'babyId': babyId, 'type': type, 'fields': fields});
    return Event(
      id: 'evt1',
      babyId: babyId,
      type: type,
      subtype: subtype,
      fields: fields,
      time: time ?? DateTime.now().toUtc(),
      note: note,
      source: source,
      createdAt: DateTime.now().toUtc(),
    );
  }
}

void main() {
  testWidgets('logging: sentence -> confirm card -> save', (tester) async {
    SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
    final prefs = await SharedPreferences.getInstance();
    final fake = _FakeApiClient(
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')],
      const StructuredResult(
        action: 'create',
        events: [
          StructuredEvent(
            type: 'feeding',
            subtype: 'formula',
            fields: {'amount_ml': 120},
            confidence: 'high',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(fake),
        ],
        child: const DaybyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log')); // switch from Home to the Log tab
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'fed 120 ml');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    // The app confirms its understanding in a chat bubble (not the raw words).
    expect(find.text('Feeding · formula · 120 ml'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.saved, hasLength(1));
    expect(fake.saved.first['type'], 'feeding');
    expect(find.text('Saved to the timeline'), findsOneWidget);
  });
}
