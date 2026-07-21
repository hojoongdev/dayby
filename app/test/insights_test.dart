import 'package:dayby/api/api_client.dart';
import 'package:dayby/auth.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/models/insights.dart';
import 'package:dayby/models/tip.dart';
import 'package:dayby/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient(this.insightsResult);

  final Insights insightsResult;

  @override
  Future<AuthConfig> authConfig() async => const AuthConfig();

  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')];

  @override
  Future<List<Event>> listEvents({String? babyId, String? type, int limit = 100}) async =>
      const [];

  @override
  Future<AssistantTips> tips({required String babyId, String? lang}) async =>
      const AssistantTips(lang: 'en');

  @override
  Future<Insights> insights({required String babyId, String? lang}) async =>
      insightsResult;
}

Future<void> _launch(WidgetTester tester, Insights insights) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(_FakeApiClient(insights)),
      ],
      child: const DaybyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the dashboard shows next-up predictions and a trend', (tester) async {
    await _launch(
      tester,
      Insights(
        predictions: [
          Prediction(
            type: 'feeding',
            at: DateTime.now().add(const Duration(hours: 1)),
            basis: 'usually about every 3h',
          ),
        ],
        observations: const ['Night feeds are down to about one.'],
      ),
    );

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Next feeding'), findsOneWidget);
    expect(find.text('usually about every 3h'), findsOneWidget);
    expect(find.text('Night feeds are down to about one.'), findsOneWidget);
  });

  testWidgets('with nothing to say the insights card stays out of the way',
      (tester) async {
    await _launch(tester, const Insights());
    expect(find.text('Insights'), findsNothing);
  });
}
