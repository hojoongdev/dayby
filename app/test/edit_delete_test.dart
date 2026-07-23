import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _logged = Event(
  id: 'e1',
  babyId: 'baby1',
  type: 'feeding',
  subtype: 'formula',
  fields: const {'amount_ml': 120, 'brand': 'hipp'},
  time: DateTime.now().toUtc(),
  createdAt: DateTime.now().toUtc(),
);

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.result);

  /// What the server makes of whatever is typed.
  final StructuredResult result;

  String? deleted;
  Map<String, dynamic>? patched;

  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')];

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    int limit = 100,
  }) async => [_logged];

  @override
  Future<StructuredResult> ingestText(
    String text, {
    List<Turn> history = const [],
    List<String> languages = const [],
  }) async => result;

  @override
  Future<void> deleteEvent(String id) async => deleted = id;

  @override
  Future<Event> updateEvent(
    String id, {
    String? type,
    String? subtype,
    Map<String, dynamic>? fields,
    DateTime? time,
    String? note,
  }) async {
    patched = {'id': id, 'fields': fields, 'time': time};
    return _logged;
  }
}

Future<_FakeApiClient> _openChat(WidgetTester tester, StructuredResult result,
    {required String saying}) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  final api = _FakeApiClient(result);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(api),
      ],
      child: const DaybyApp(),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.mic));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), saying);
  // The send button only exists once there is something typed to send.
  await tester.pump();
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();

  return api;
}

void main() {
  testWidgets('deleting shows what is about to go, and only goes if confirmed',
      (tester) async {
    final api = await _openChat(
      tester,
      StructuredResult(action: 'delete', target: _logged, reply: 'Delete that?'),
      saying: 'delete the last feeding',
    );

    // The record itself, not just the word "it".
    expect(find.text('Delete this?'), findsOneWidget);
    expect(find.text('Feeding · formula · 120 ml · brand hipp'), findsOneWidget);

    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(api.deleted, isNull);
    expect(find.text('Delete this?'), findsNothing);
  });

  testWidgets('confirming a delete removes the record it showed', (tester) async {
    final api = await _openChat(
      tester,
      StructuredResult(action: 'delete', target: _logged, reply: 'Delete that?'),
      saying: 'delete the last feeding',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(api.deleted, 'e1');
    expect(find.text('Deleted'), findsOneWidget);
  });

  testWidgets('a correction shows what the record becomes', (tester) async {
    final api = await _openChat(
      tester,
      StructuredResult(
        action: 'update',
        target: _logged,
        // Only the amount changed, and no time: the record must not move.
        events: const [
          StructuredEvent(type: 'feeding', fields: {'amount_ml': 150}),
        ],
        reply: 'Change it to 150?',
      ),
      saying: 'actually it was 150',
    );

    // The merged result, not just the patch: the brand survives the correction.
    expect(find.text('Feeding · formula · 150 ml · brand hipp'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Change'));
    await tester.pumpAndSettle();

    expect(api.patched?['id'], 'e1');
    expect(api.patched?['fields'], {'amount_ml': 150});
    expect(api.patched?['time'], isNull);
  });
}
