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
  _FakeApiClient(this.babies);

  final List<Baby> babies;

  @override
  Future<List<Baby>> listBabies() async => babies;

  @override
  Future<List<Event>> listEvents({String? babyId, String? type, int limit = 100}) async =>
      const [];
}

void main() {
  testWidgets('settings shows family info and reset returns to onboarding',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'family_id': 'fam1',
      'family_name': 'Kim family',
      'invite_code': 'a1b2c3',
      'selected_baby_id': 'baby1',
    });
    final prefs = await SharedPreferences.getInstance();
    final fake = _FakeApiClient(
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')],
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

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Kim family'), findsOneWidget);
    expect(find.text('a1b2c3'), findsOneWidget);
    expect(find.text('Ari'), findsOneWidget);

    // Reset is below the fold now (units section) — scroll it into view.
    await tester.drag(find.text('Ari'), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset app'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Dayby'), findsOneWidget);
  });
}
