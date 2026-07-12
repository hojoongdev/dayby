import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/models/tip.dart';
import 'package:dayby/providers.dart';
import 'package:dayby/reminders.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tray is the operating system's. What is testable is what we leave in it.
class _FakeReminders implements Reminders {
  DateTime? at;
  String? text;
  int scheduled = 0;

  @override
  Future<void> schedule({DateTime? at, String? text}) async {
    this.at = at;
    this.text = text;
    scheduled++;
  }
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.tipsResult);

  AssistantTips tipsResult;

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
  Future<AssistantTips> tips({required String babyId, String? lang}) async =>
      tipsResult;
}

Future<_FakeReminders> _launch(WidgetTester tester, AssistantTips tips) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  final reminders = _FakeReminders();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(_FakeApiClient(tips)),
        remindersProvider.overrideWithValue(reminders),
      ],
      child: const DaybyApp(),
    ),
  );
  await tester.pumpAndSettle();
  return reminders;
}

void main() {
  testWidgets('the nudge the server wrote is left with the phone, for later',
      (tester) async {
    final due = DateTime.now().add(const Duration(hours: 3));
    final reminders = await _launch(
      tester,
      AssistantTips(
        lang: 'en',
        tips: const [Tip(kind: 'tip', text: 'Five-month-olds start rolling over.')],
        remindAt: due,
        reminder: 'It has been a while since the last feeding — worth a look.',
      ),
    );

    expect(reminders.at, due);
    expect(reminders.text,
        'It has been a while since the last feeding — worth a look.');
  });

  testWidgets('the line meant for later is not one of the lines shown now',
      (tester) async {
    await _launch(
      tester,
      AssistantTips(
        lang: 'en',
        tips: const [Tip(kind: 'nudge', text: 'It has been 4 hours since the feed.')],
        remindAt: DateTime.now().add(const Duration(hours: 3)),
        reminder: 'Later: worth a look.',
      ),
    );

    expect(find.text('It has been 4 hours since the feed.'), findsOneWidget);
    expect(find.text('Later: worth a look.'), findsNothing);
  });

  testWidgets('nothing due means nothing pending', (tester) async {
    final reminders = await _launch(tester, const AssistantTips(lang: 'en'));

    // Still called: clearing is exactly what should happen once it is logged.
    expect(reminders.scheduled, 1);
    expect(reminders.at, isNull);
    expect(reminders.text, isNull);
  });
}
