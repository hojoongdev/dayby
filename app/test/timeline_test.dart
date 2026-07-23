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
  _FakeApiClient(this.babies, this.events);

  final List<Baby> babies;
  final List<Event> events;

  @override
  Future<List<Baby>> listBabies() async => babies;

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    int limit = 100,
  }) async => events;
}

void main() {
  testWidgets('timeline groups events by day with summaries', (tester) async {
    SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc();
    final fake = _FakeApiClient(
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Ari')],
      [
        Event(
          id: 'e1',
          babyId: 'baby1',
          type: 'feeding',
          subtype: 'formula',
          fields: const {'amount_ml': 120},
          time: now,
          createdAt: now,
        ),
        Event(
          id: 'e2',
          babyId: 'baby1',
          type: 'diaper',
          subtype: 'wet',
          time: now.subtract(const Duration(days: 1)),
          createdAt: now,
        ),
      ],
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

    await tester.tap(find.text('Records'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Feeding · formula · 120 ml'), findsOneWidget);
    expect(find.text('Diaper · wet'), findsOneWidget);
  });
}
