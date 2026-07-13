import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.replies);

  /// What the server makes of each thing typed, in order. A null entry fails the request.
  final List<StructuredResult?> replies;

  /// The history the app sent with each utterance.
  final List<List<Turn>> sent = [];
  int _call = 0;

  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')];

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    int limit = 100,
  }) async => const [];

  @override
  Future<StructuredResult> ingestText(
    String text, {
    List<Turn> history = const [],
  }) async {
    sent.add(history);
    final reply = replies[_call++];
    if (reply == null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/ingest/text'),
        type: DioExceptionType.connectionError,
      );
    }
    return reply;
  }

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
  }) async => Event(
        id: 'evt1',
        babyId: babyId,
        type: type,
        subtype: subtype,
        fields: fields,
        time: time ?? DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
      );
}

Future<_FakeApiClient> _openChat(
  WidgetTester tester,
  List<StructuredResult?> replies,
) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  final api = _FakeApiClient(replies);

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
  await tester.tap(find.text('Log'));
  await tester.pumpAndSettle();
  return api;
}

Future<void> _say(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.tap(find.byIcon(Icons.send));
  await tester.pumpAndSettle();
}

List<String> _lines(List<Turn> turns) =>
    [for (final t in turns) '${t.fromUser ? 'user' : 'app'}: ${t.text}'];

void main() {
  testWidgets('a follow-up carries the chat so far, saved lines included',
      (tester) async {
    final api = await _openChat(tester, [
      const StructuredResult(
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
      const StructuredResult(action: 'update', reply: 'Change it to 200?'),
    ]);

    await _say(tester, 'formula 120ml');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await _say(tester, 'actually 200');

    // Nothing had been said before the first utterance.
    expect(api.sent.first, isEmpty);

    expect(_lines(api.sent.last), [
      'user: formula 120ml',
      'app: Formula, 120 ml. Save it?',
      // The saved line goes too, so the server knows this one is really in the timeline.
      'app: Feeding · formula · 120 ml — saved to the timeline',
    ]);
  });

  testWidgets('a failed request leaves the conversation alone', (tester) async {
    final api = await _openChat(tester, [
      const StructuredResult(action: 'query', reply: 'Four feeds today.'),
      null, // the network drops
      const StructuredResult(action: 'query', reply: 'Three yesterday.'),
    ]);

    await _say(tester, 'how many feeds today?');
    await _say(tester, 'and yesterday?');
    await _say(tester, 'and yesterday?'); // retried

    // What they said stands. The error bubble is plumbing and does not.
    expect(_lines(api.sent.last), [
      'user: how many feeds today?',
      'app: Four feeds today.',
      'user: and yesterday?',
    ]);
  });
}
