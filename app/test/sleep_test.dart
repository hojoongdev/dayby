import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:dayby/units.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.events);

  final List<Event> events;

  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')];

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    int limit = 100,
  }) async => events;
}

Event _sleep(String subtype, Duration ago, {Map<String, dynamic> fields = const {}}) =>
    Event(
      id: 's-$subtype',
      babyId: 'baby1',
      type: 'sleep',
      subtype: subtype,
      fields: fields,
      time: DateTime.now().toUtc().subtract(ago),
      createdAt: DateTime.now().toUtc(),
    );

Future<void> _pumpHome(WidgetTester tester, List<Event> events) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(_FakeApiClient(events)),
      ],
      child: const DaybyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a nap reads like a nap, not like a number of minutes', () {
    expect(formatMinutes(40), '40m');
    expect(formatMinutes(135), '2h 15m');
    expect(formatMinutes(180), '3h');
    expect(formatField('duration_min', 135, const UnitPrefs()), '2h 15m');
  });

  testWidgets('a sleep that has not ended means she is asleep right now',
      (tester) async {
    await _pumpHome(tester, [_sleep('start', const Duration(minutes: 95))]);

    // The headline is how long she has been down, not "95m ago", and it says asleep.
    expect(find.text('Asleep'), findsOneWidget);
    expect(find.text('1h 35m'), findsOneWidget);
    expect(find.text('1h 35m ago'), findsNothing);
  });

  testWidgets('once she is up, the card is about the nap she had', (tester) async {
    await _pumpHome(tester, [
      _sleep('end', const Duration(minutes: 20), fields: const {'duration_min': 135}),
      _sleep('start', const Duration(minutes: 155)),
    ]);

    expect(find.text('20m ago'), findsOneWidget);
    expect(find.text('Slept 2h 15m'), findsOneWidget);
  });
}
