import 'package:dayby/api/api_client.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/models/insights.dart';
import 'package:dayby/models/tip.dart';
import 'package:dayby/providers.dart';
import 'package:dayby/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime _ago(int min) => DateTime.now().subtract(Duration(minutes: min));
DateTime _ahead(int min) => DateTime.now().add(Duration(minutes: min));

class _Fake extends ApiClient {
  final List<Map<String, dynamic>> logged = [];

  @override
  Future<List<Baby>> listBabies() async => [
        Baby(id: 'baby1', familyId: 'fam1', name: 'Haein', birthdate: DateTime(2026, 2, 18)),
      ];

  @override
  Future<AssistantTips> tips({required String babyId, String? lang}) async =>
      const AssistantTips();

  @override
  Future<List<Event>> listEvents({String? babyId, String? type, int limit = 100}) async => [
        Event(id: 'f', babyId: 'baby1', type: 'feeding', subtype: 'formula',
            fields: const {'amount_ml': 160}, time: _ago(30), createdAt: _ago(30)),
      ];

  @override
  Future<Insights> insights({required String babyId, String? lang}) async => Insights(
        predictions: [
          Prediction(type: 'feeding', at: _ahead(120), basis: 'usually about every 2h 30m'),
        ],
      );

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
  }) async {
    logged.add({'type': type, 'subtype': subtype});
    return Event(
      id: 'x', babyId: babyId, type: type, subtype: subtype,
      time: DateTime.now().toUtc(), createdAt: DateTime.now().toUtc(),
    );
  }
}

Future<_Fake> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(
      {'family_id': 'fam1', 'selected_baby_id': 'baby1'});
  final prefs = await SharedPreferences.getInstance();
  final fake = _Fake();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('the feeding card shows what and how long ago, with the usual gap',
      (tester) async {
    await _pump(tester);

    expect(find.text('Haein'), findsOneWidget);
    expect(find.textContaining('D+'), findsOneWidget);
    expect(find.text('Formula · 160 ml'), findsOneWidget);
    expect(find.text('since feeding'), findsOneWidget);
    // nextAt - at = 150 min, shown as the typical gap.
    expect(find.text('~2h 30m'), findsOneWidget);
  });

  testWidgets('a quick-log button logs that kind at a tap', (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.text('Bath'));
    await tester.pumpAndSettle();

    expect(fake.logged, hasLength(1));
    expect(fake.logged.first['type'], 'bath');
  });
}
