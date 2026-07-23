import 'package:dayby/api/api_client.dart';
import 'package:dayby/lang.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
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
}

Future<ProviderContainer> _openSettings(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      apiClientProvider.overrideWithValue(_FakeApiClient()),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const DaybyApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
  return container;
}

/// Settings is a long list, and a ListView only builds what is near the viewport — so the
/// row has to be scrolled to before it exists at all. Dragging a widget known to be inside
/// the list picks out the right scrollable; the other tabs are still in the IndexedStack,
/// with scrollables of their own.
Future<void> _open(WidgetTester tester, String row) async {
  await tester.drag(find.text('Add a baby'), const Offset(0, -300));
  await tester.pumpAndSettle();
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('units and languages are behind their own screens now', (tester) async {
    await _openSettings(tester);

    // The four dropdowns used to sit on the settings page itself.
    expect(find.text('Feeding volume'), findsNothing);

    await _open(tester, 'Units');

    expect(find.text('Feeding volume'), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
  });

  testWidgets('you cannot untick the last language you speak', (tester) async {
    final container = await _openSettings(tester);

    await _open(tester, 'Languages');

    // Start from the default, Korean and English.
    expect(container.read(spokenLanguagesProvider), kDefaultLanguages);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'English'));
    await tester.pumpAndSettle();
    expect(container.read(spokenLanguagesProvider), ['ko']);

    // Unticking Korean too would leave the transcriber free to reach for any language on
    // earth, which is the one thing this setting is for. So it will not come off.
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Korean'));
    await tester.pumpAndSettle();
    expect(container.read(spokenLanguagesProvider), ['ko']);
  });

  testWidgets('Dayby cannot answer in a language you just said you do not speak',
      (tester) async {
    final container = await _openSettings(tester);
    await container.read(spokenLanguagesProvider.notifier).set(['ko', 'en']);
    await container.read(assistantLangProvider.notifier).set('en');

    await container.read(spokenLanguagesProvider.notifier).set(['ko']);

    expect(container.read(assistantLangProvider), 'ko');
  });
}
