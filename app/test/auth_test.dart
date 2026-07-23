import 'package:dayby/api/api_client.dart';
import 'package:dayby/auth.dart';
import 'package:dayby/google.dart';
import 'package:dayby/main.dart';
import 'package:dayby/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google's sheet needs a Google project and a phone. What the app does with what
/// comes back from it does not.
class _FakeGoogle implements GoogleIdentity {
  _FakeGoogle({this.isAvailable = true});

  @override
  final bool isAvailable;

  @override
  Future<String?> idToken() async => 'a-google-id-token';
}

/// The keychain is platform code. A map does the job here.
class _FakeTokenStore implements TokenStore {
  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;

  @override
  Future<void> clear() async => tokens = null;
}

class _FakeApiClient extends ApiClient {
  String? signedInAs;

  @override
  Future<Session> signIn(String providerToken) async {
    signedInAs = providerToken;
    return const Session(
      tokens: AuthTokens(access: 'access-1', refresh: 'refresh-1'),
      user: AuthUser(id: 'u1', email: 'mum@dayby.app'),
      // A brand new account belongs to no family yet.
      familyId: null,
    );
  }
}

void main() {
  testWidgets('signing in leads to the family you do not have yet',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApiClient();
    final store = _FakeTokenStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(api),
          anonymousApiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(store),
          authConfigProvider.overrideWith(
            (ref) async => const AuthConfig(enabled: true, provider: 'mock'),
          ),
        ],
        child: const DaybyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // A server that asks for a sign-in gets one before anything else.
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Welcome to Dayby'), findsNothing);

    await tester.enterText(find.byType(TextField), 'mum@dayby.app');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(api.signedInAs, 'mum@dayby.app');
    // Kept, so the next launch does not ask again.
    expect(store.tokens?.refresh, 'refresh-1');
    // Signed in, but with no family: that is the next screen, not an error.
    expect(find.text('Welcome to Dayby'), findsOneWidget);
    expect(find.text('Join a family with an invite code'), findsOneWidget);
  });

  testWidgets("Google's token is what gets handed to the server", (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(api),
          anonymousApiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(_FakeTokenStore()),
          googleIdentityProvider.overrideWithValue(_FakeGoogle()),
          authConfigProvider.overrideWith(
            (ref) async => const AuthConfig(enabled: true, provider: 'google'),
          ),
        ],
        child: const DaybyApp(),
      ),
    );
    await tester.pumpAndSettle();

    // A Google server asks for Google, not for an email box.
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    // The app never sees anything it could have forged: it passes on what Google
    // issued, and the server checks it against Google's keys.
    expect(api.signedInAs, 'a-google-id-token');
  });

  testWidgets('a build with no client id says so instead of offering a dead button',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(api),
          anonymousApiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(_FakeTokenStore()),
          googleIdentityProvider.overrideWithValue(_FakeGoogle(isAvailable: false)),
          authConfigProvider.overrideWith(
            (ref) async => const AuthConfig(enabled: true, provider: 'google'),
          ),
        ],
        child: const DaybyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsNothing);
    expect(find.textContaining('GOOGLE_CLIENT_ID'), findsOneWidget);
  });
}
