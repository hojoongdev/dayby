import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/models/tip.dart';
import 'package:dayby/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.tipsResult);

  final AssistantTips tipsResult;

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

Future<void> _pumpDashboard(WidgetTester tester, AssistantTips tips) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(_FakeApiClient(tips)),
      ],
      child: const DaybyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the dashboard leads with what the assistant has to say',
      (tester) async {
    await _pumpDashboard(
      tester,
      const AssistantTips(
        lang: 'en',
        tips: [
          Tip(
            kind: 'nudge',
            topic: 'feeding',
            text: 'It has been 4 hours since the last feeding.',
          ),
          Tip(
            kind: 'tip',
            topic: 'development',
            text: 'Five-month-olds start rolling over.',
          ),
        ],
      ),
    );

    expect(find.text('It has been 4 hours since the last feeding.'),
        findsOneWidget);
    expect(find.text('Five-month-olds start rolling over.'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('with nothing to say the card stays out of the way',
      (tester) async {
    await _pumpDashboard(tester, const AssistantTips());

    expect(find.text('Assistant'), findsNothing);
  });
}
