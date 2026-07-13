import 'package:dayby/api/api_client.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/models/stats.dart';
import 'package:dayby/providers.dart';
import 'package:dayby/screens/stats_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A fortnight of a real-shaped baby: feeds creeping up, the night stretching out. Enough
/// days that every chart has something to draw and the axis labels are dense.
Stats _aFortnight() {
  final days = <DayStat>[];
  final rhythm = <RhythmBlock>[];

  for (var i = 0; i < 14; i++) {
    final date = '2026-06-${(20 + i).toString().padLeft(2, '0')}';
    final feeds = 8 - i ~/ 5;
    days.add(DayStat(
      date: date,
      feeds: feeds,
      feedMl: 90.0 * feeds + i * 6,
      avgFeedGapMin: 165 + i * 5,
      diapers: {'wet': 4 + i % 3, 'dirty': 2, if (i % 4 == 0) 'mixed': 1},
      napMin: 180 - i * 4,
      nightSleepMin: 400 + i * 8,
    ));

    rhythm
      ..add(RhythmBlock(date: date, type: 'sleep', startMin: 20 * 60, minutes: 240))
      ..add(RhythmBlock(date: date, type: 'sleep', startMin: 0, minutes: 300))
      ..add(RhythmBlock(date: date, type: 'sleep', startMin: 13 * 60, minutes: 90));
    for (final at in [2 * 60, 6 * 60, 10 * 60, 14 * 60, 18 * 60, 22 * 60]) {
      rhythm.add(RhythmBlock(date: date, type: 'feeding', startMin: at));
    }
    for (final at in [7 * 60, 12 * 60, 17 * 60, 21 * 60]) {
      rhythm.add(RhythmBlock(date: date, type: 'diaper', startMin: at));
    }
  }

  return Stats(
    days: days,
    rhythm: rhythm,
    growth: [
      for (var i = 0; i < 5; i++)
        GrowthPoint(
          time: DateTime(2026, 6, 20 + i * 3),
          weightKg: 6.0 + i * 0.22,
          heightCm: 60.0 + i * 0.9,
        ),
    ],
  );
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({this.fixture = const Stats()});

  final Stats fixture;

  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Haein')];

  @override
  Future<Stats> stats({required String babyId, int days = 14}) async => fixture;
}

Future<void> _pump(WidgetTester tester, Stats stats) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();

  // 375pt is the narrowest current iPhone (SE, mini) -- where a chart card runs out of
  // room first; the default 800px test surface never would. The height is deliberately
  // tall so the ListView builds every card at once and the overflow check covers all of
  // them, not just the ones above the fold.
  tester.view.physicalSize = const Size(1125, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(_FakeApiClient(fixture: stats)),
      ],
      child: const MaterialApp(home: StatsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every chart renders at phone width without overflow', (tester) async {
    await _pump(tester, _aFortnight());

    // An overflowing Row or Column throws during layout; the framework holds it here.
    expect(tester.takeException(), isNull);

    // The first card through the last: if they all built, the whole list laid out and the
    // overflow check above saw every one of them.
    expect(find.text('The shape of a day'), findsOneWidget);
    expect(find.text('Feeding'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Nappies'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('Height'), findsOneWidget);
  });

  testWidgets('with nothing logged it says so instead of drawing empty axes',
      (tester) async {
    await _pump(tester, const Stats());

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Nothing logged yet'), findsOneWidget);
  });
}
