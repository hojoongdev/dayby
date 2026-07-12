import 'package:dayby/api/api_client.dart';
import 'package:dayby/app_lock.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sensor is the phone's. What is testable is what we do with its answer.
class _FakeLock implements AppLock {
  _FakeLock({this.allow = true});

  bool allow;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> unlock() async {
    asked++;
    return allow;
  }
}

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

Future<void> _launch(WidgetTester tester, _FakeLock lock, {bool locked = true}) async {
  SharedPreferences.setMockInitialValues({
    'family_id': 'fam1',
    'app_lock': locked,
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(_FakeApiClient()),
        appLockProvider.overrideWithValue(lock),
      ],
      child: const DaybyApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a locked app shows nothing until the phone says who this is',
      (tester) async {
    final lock = _FakeLock(allow: false);
    await _launch(tester, lock);

    expect(lock.asked, 1); // asked on its own, without a button to press first
    expect(find.text('Dayby is locked'), findsOneWidget);
    expect(find.text('Ari'), findsNothing);

    // Refused: still locked, and it will ask again.
    expect(find.text('Try again'), findsOneWidget);

    lock.allow = true;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Dayby is locked'), findsNothing);
    expect(find.text('Ari'), findsOneWidget);
  });

  testWidgets('with the lock off it opens straight to the baby', (tester) async {
    final lock = _FakeLock();
    await _launch(tester, lock, locked: false);

    expect(lock.asked, 0);
    expect(find.text('Ari'), findsOneWidget);
  });

  testWidgets('leaving the app locks it again', (tester) async {
    final lock = _FakeLock();
    await _launch(tester, lock);
    await tester.pumpAndSettle();
    expect(find.text('Ari'), findsOneWidget);

    // Into the app switcher, where the screenshot lives.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.text('Dayby is locked'), findsOneWidget);
  });
}
