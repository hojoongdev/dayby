import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'app_lock.dart';
import 'auth.dart';
import 'google.dart';
import 'live.dart';
import 'models/event.dart';
import 'models/family.dart';
import 'models/tip.dart';
import 'models/wrapped.dart';
import 'reminders.dart';
import 'units.dart';
import 'voice.dart';

const familyIdKey = 'family_id';
const familyNameKey = 'family_name';
const inviteCodeKey = 'invite_code';
const selectedBabyIdKey = 'selected_baby_id';
const assistantLangKey = 'assistant_lang';
const appLockKey = 'app_lock';

final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in main'),
);

final tokenStoreProvider = Provider<TokenStore>((ref) => const SecureTokenStore());

/// A client with no session attached, for the three calls that cannot have one:
/// asking whether a sign-in is needed, signing in, and refreshing. Separate from
/// apiClientProvider, which needs a session and would therefore be a circle.
final anonymousApiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final apiClientProvider = Provider<ApiClient>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return ApiClient(
    familyId: prefs.getString(familyIdKey),
    tokens: ref.watch(sessionProvider).value?.tokens,
    onTokensRefreshed: (tokens) => ref.read(tokenStoreProvider).write(tokens),
  );
});

/// Whether this server asks anyone to sign in, and with what. A server that cannot
/// be reached is treated as one that does not ask.
final authConfigProvider = FutureProvider<AuthConfig>((ref) async {
  try {
    return await ref.watch(anonymousApiClientProvider).authConfig();
  } catch (_) {
    return const AuthConfig();
  }
});

/// The signed-in session, restored from the keychain on launch. Null means signed
/// out — which is also the answer when the server is not asking.
class SessionNotifier extends AsyncNotifier<Session?> {
  ApiClient get _anonymous => ref.read(anonymousApiClientProvider);

  @override
  Future<Session?> build() async {
    // A server that never asks anyone to sign in has no session to restore, and
    // there is no reason to open the keychain looking for one.
    if (!(await ref.watch(authConfigProvider.future)).enabled) return null;

    final store = ref.watch(tokenStoreProvider);
    final stored = await store.read();
    if (stored == null) return null;

    try {
      // The stored refresh token is the session. Trading it in gets a live access
      // token back, and tells us which family this account ended up in.
      return await _remember(await _anonymous.refreshSession(stored.refresh));
    } catch (_) {
      await store.clear();
      return null;
    }
  }

  Future<Session> _remember(Session session) async {
    await ref.read(tokenStoreProvider).write(session.tokens);
    final familyId = session.familyId;
    if (familyId != null) {
      await ref.read(familyIdProvider.notifier).set(familyId);
    }
    return session;
  }

  Future<void> signIn(String providerToken) async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _remember(await _anonymous.signIn(providerToken)));
    } catch (error, stack) {
      state = AsyncError(error, stack);
      rethrow; // the sign-in screen says what went wrong; the app stays put
    }
  }

  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clear();
    await ref.read(familyIdProvider.notifier).clear();
    state = const AsyncData(null);
  }

  /// After the family is created or joined, the session knows where it belongs.
  void joinedFamily(String familyId) {
    final session = state.value;
    if (session == null) return;
    state = AsyncData(Session(
      tokens: session.tokens,
      user: session.user,
      familyId: familyId,
    ));
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class FamilyIdNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(sharedPrefsProvider).getString(familyIdKey);

  Future<void> set(String id) async {
    await ref.read(sharedPrefsProvider).setString(familyIdKey, id);
    state = id;
  }

  Future<void> clear() async {
    await ref.read(sharedPrefsProvider).remove(familyIdKey);
    state = null;
  }
}

final familyIdProvider =
    NotifierProvider<FamilyIdNotifier, String?>(FamilyIdNotifier.new);

/// The current family's name and invite code, persisted at onboarding.
final familyProvider = Provider<({String name, String code})?>((ref) {
  final id = ref.watch(familyIdProvider);
  if (id == null) return null;
  final prefs = ref.watch(sharedPrefsProvider);
  return (
    name: prefs.getString(familyNameKey) ?? 'Your family',
    code: prefs.getString(inviteCodeKey) ?? '',
  );
});

final babiesProvider = FutureProvider<List<Baby>>(
  (ref) => ref.watch(apiClientProvider).listBabies(),
);

class SelectedBabyIdNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(sharedPrefsProvider).getString(selectedBabyIdKey);

  Future<void> set(String id) async {
    await ref.read(sharedPrefsProvider).setString(selectedBabyIdKey, id);
    state = id;
  }
}

final selectedBabyIdProvider =
    NotifierProvider<SelectedBabyIdNotifier, String?>(SelectedBabyIdNotifier.new);

/// The baby currently being logged for: the explicit selection when it still
/// exists, otherwise the first baby. Null only before any baby is added.
final activeBabyProvider = Provider<Baby?>((ref) {
  final babies = ref.watch(babiesProvider).value ?? const <Baby>[];
  if (babies.isEmpty) return null;
  final id = ref.watch(selectedBabyIdProvider);
  return babies.firstWhere((b) => b.id == id, orElse: () => babies.first);
});

/// Timeline for one baby, newest first. Invalidate to refetch after a save.
final eventsProvider = FutureProvider.family<List<Event>, String>(
  (ref, babyId) => ref.watch(apiClientProvider).listEvents(babyId: babyId),
);

/// The camera / library picker. Behind a provider so a test can hand the screen a
/// picture without opening a platform dialog.
final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

/// The microphone. Behind a provider for the same reason: a test can talk to the app
/// without one, which is the only way to cover what a second impatient tap does.
final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = VoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

final liveFeedProvider = Provider<LiveFeed>((ref) => const WebSocketLiveFeed());

/// Where a nudge is left for the operating system to deliver later.
final remindersProvider = Provider<Reminders>((ref) => LocalReminders());

final appLockProvider = Provider<AppLock>((ref) => BiometricAppLock());

final googleIdentityProvider =
    Provider<GoogleIdentity>((ref) => RealGoogleIdentity());

/// Whether this device can ask for a face or a fingerprint at all.
final biometricsAvailableProvider =
    FutureProvider<bool>((ref) => ref.watch(appLockProvider).isAvailable());

/// Whether the caregiver has asked for the app to be locked, persisted.
class AppLockEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(appLockKey) ?? false;

  Future<void> set(bool enabled) async {
    await ref.read(sharedPrefsProvider).setBool(appLockKey, enabled);
    state = enabled;
  }
}

final appLockEnabledProvider =
    NotifierProvider<AppLockEnabledNotifier, bool>(AppLockEnabledNotifier.new);

/// Whether it is unlocked right now. Not persisted — going away locks it again,
/// which is the entire point.
class UnlockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
  void lock() => state = false;
}

final unlockedProvider =
    NotifierProvider<UnlockedNotifier, bool>(UnlockedNotifier.new);

/// Every event the family logs, as it lands — including the ones logged on the
/// other parent's phone. The server tails a MongoDB change stream; this is the
/// end of that wire.
final liveEventsProvider = StreamProvider<Event>((ref) {
  final familyId = ref.watch(familyIdProvider);
  if (familyId == null) return const Stream<Event>.empty();

  final connection = ref.watch(liveFeedProvider).connect(
        familyId,
        token: ref.watch(sessionProvider).value?.tokens.access,
      );
  ref.onDispose(connection.close);
  return connection.events;
});

/// A stored photo, fetched through the API client so it carries the family header.
/// Cached by id, which is safe: a photo never changes once written.
final photoProvider = FutureProvider.family<Uint8List, String>(
  (ref, photoId) => ref.watch(apiClientProvider).photoBytes(photoId),
);

/// The assistant's proactive lines for one baby. Invalidated on every save: a
/// nudge about a missing feed has to disappear the moment the feed is logged.
final tipsProvider = FutureProvider.family<AssistantTips, String>(
  (ref, babyId) => ref.watch(apiClientProvider).tips(
        babyId: babyId,
        lang: ref.watch(assistantLangProvider),
      ),
);

/// The lifetime retrospective for one baby.
final wrappedProvider = FutureProvider.family<Wrapped, String>(
  (ref, babyId) => ref.watch(apiClientProvider).wrapped(
        babyId: babyId,
        lang: ref.watch(assistantLangProvider),
      ),
);

/// The language the assistant speaks back in ("ko" | "en"), for the surfaces where
/// nobody has said anything for it to detect: the tips on Home and the wrapped story.
/// What the caregiver *says* is always detected from the words themselves.
/// Defaults to Korean — Dayby is a Korean-first app.
class AssistantLangNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(sharedPrefsProvider).getString(assistantLangKey) ?? 'ko';

  Future<void> set(String lang) async {
    await ref.read(sharedPrefsProvider).setString(assistantLangKey, lang);
    state = lang;
  }
}

final assistantLangProvider =
    NotifierProvider<AssistantLangNotifier, String>(AssistantLangNotifier.new);

/// The caregiver's preferred display units, persisted.
class UnitPrefsNotifier extends Notifier<UnitPrefs> {
  @override
  UnitPrefs build() {
    final p = ref.watch(sharedPrefsProvider);
    return UnitPrefs(
      temp: p.getString('unit_temp') ?? 'c',
      weight: p.getString('unit_weight') ?? 'kg',
      length: p.getString('unit_length') ?? 'cm',
      volume: p.getString('unit_volume') ?? 'ml',
    );
  }

  Future<void> set({String? temp, String? weight, String? length, String? volume}) async {
    final p = ref.read(sharedPrefsProvider);
    if (temp != null) await p.setString('unit_temp', temp);
    if (weight != null) await p.setString('unit_weight', weight);
    if (length != null) await p.setString('unit_length', length);
    if (volume != null) await p.setString('unit_volume', volume);
    state = state.copyWith(temp: temp, weight: weight, length: length, volume: volume);
  }
}

final unitPrefsProvider =
    NotifierProvider<UnitPrefsNotifier, UnitPrefs>(UnitPrefsNotifier.new);
