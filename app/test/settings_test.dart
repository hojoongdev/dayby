import 'package:dayby/api/api_client.dart';
import 'package:dayby/main.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// share_plus itself does not re-export the platform, only what a caller needs.
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
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

class _FakeShare extends SharePlatform with MockPlatformInterfaceMixin {
  ShareParams? shared;

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared = params;
    return const ShareResult('', ShareResultStatus.success);
  }
}

Future<void> _openSettings(WidgetTester tester) async {
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

  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sharing hands over the code and enough words to make sense of it',
      (tester) async {
    final share = _FakeShare();
    SharePlatform.instance = share;

    await _openSettings(tester);
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    // A bare code means nothing to the parent who receives it.
    expect(share.shared?.text, contains('a1b2c3'));
    expect(share.shared?.text, contains('Dayby'));
  });

  testWidgets('settings shows family info and reset returns to onboarding',
      (tester) async {
    await _openSettings(tester);

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
