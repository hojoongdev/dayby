import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/models/wrapped.dart';
import 'package:dayby/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  Future<Wrapped> wrapped({required String babyId, String? lang}) async => Wrapped(
        lang: 'en',
        story: 'You changed 1031 diapers, and Ari grew from 3.3 kg to 7.2 kg.',
        stats: WrappedStats(
          daysTracked: 160,
          totalEvents: 2085,
          feedings: 1033,
          totalFeedMl: 135040,
          nightFeeds: 151,
          diapers: 1031,
          busiestDay: '2026-07-06',
          busiestDayEvents: 16,
          firstWeightKg: 3.3,
          lastWeightKg: 7.2,
          milestones: [
            Milestone(time: DateTime.utc(2026, 3, 14), text: 'first real smile'),
          ],
        ),
      );
}

void main() {
  testWidgets('the keepsake leads with the story, then the big numbers',
      (tester) async {
    SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(_FakeApiClient()),
        ],
        child: const DaybyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Your story with Ari'));
    await tester.pumpAndSettle();

    expect(
      find.text('You changed 1031 diapers, and Ari grew from 3.3 kg to 7.2 kg.'),
      findsOneWidget,
    );
    // Counted, comma'd, and in the caregiver's units.
    expect(find.text('1,031'), findsOneWidget);
    expect(find.text('151'), findsOneWidget);
    expect(find.text('135.0 L'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('first real smile'), 200);
    expect(find.text('first real smile'), findsOneWidget);
  });
}
