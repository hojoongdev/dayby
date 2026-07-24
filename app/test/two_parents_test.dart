import 'package:dayby/api/api_client.dart';
import 'package:dayby/auth.dart';
import 'package:dayby/models/event.dart';
import 'package:dayby/models/family.dart';
import 'package:dayby/providers.dart';
import 'package:dayby/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _me = AuthUser(id: 'u-dad', email: 'dad@dayby.app', name: 'Hojoong');
const _her = AuthUser(id: 'u-mum', email: 'mum@dayby.app', name: 'Sujin');

Event _logged(String type, String by) => Event(
      id: 'e-$type',
      babyId: 'baby1',
      type: type,
      time: DateTime.utc(2026, 7, 13, 9),
      createdBy: by,
      createdAt: DateTime.utc(2026, 7, 13, 9),
    );

class _FakeApiClient extends ApiClient {
  @override
  Future<List<Baby>> listBabies() async =>
      const [Baby(id: 'baby1', familyId: 'fam1', name: 'Haein')];

  @override
  Future<List<AuthUser>> familyMembers() async => const [_me, _her];

  @override
  Future<List<Event>> listEvents({
    String? babyId,
    String? type,
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async => [_logged('feeding', _her.id), _logged('diaper', _me.id)];
}

class _SignedIn extends SessionNotifier {
  @override
  Future<Session?> build() async => const Session(
        tokens: AuthTokens(access: 'a', refresh: 'r'),
        user: _me,
        familyId: 'fam1',
      );
}

void main() {
  testWidgets('the timeline names the parent who logged it, and never you',
      (tester) async {
    SharedPreferences.setMockInitialValues({'family_id': 'fam1'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(_FakeApiClient()),
          sessionProvider.overrideWith(_SignedIn.new),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Records'));
    await tester.pumpAndSettle();

    // Half asleep at 3am, what you need to know is whether *she* already did it.
    expect(find.text('Sujin'), findsOneWidget);
    // And not that you did the one you remember doing.
    expect(find.text('Hojoong'), findsNothing);
  });
}
