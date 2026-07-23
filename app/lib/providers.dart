import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'app_lock.dart';
import 'auth.dart';
import 'config.dart';
import 'google.dart';
import 'intent_bridge.dart';
import 'lang.dart';
import 'live.dart';
import 'models/event.dart';
import 'models/family.dart';
import 'models/insights.dart';
import 'models/routine.dart';
import 'models/stats.dart';
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
const spokenLanguagesKey = 'spoken_languages';
const appLockKey = 'app_lock';
const themeModeKey = 'theme_mode';
const serverUrlKey = 'server_url';
const caregiverIdKey = 'caregiver_id';

final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in main'),
);

final tokenStoreProvider = Provider<TokenStore>((ref) => const SecureTokenStore());

/// Which backend the app talks to. Editable at runtime so anyone can run their own
/// server (locally, on AWS, anywhere) and point the app at it. Defaults to whatever
/// was baked in at build time. Changing it rebuilds every client that reads it.
class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() {
    final saved = ref.watch(sharedPrefsProvider).getString(serverUrlKey);
    return (saved != null && saved.isNotEmpty) ? saved : kApiBaseUrl;
  }

  Future<void> set(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    await ref.read(sharedPrefsProvider).setString(serverUrlKey, clean);
    state = clean;
  }
}

final serverUrlProvider =
    NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);

/// A client with no session attached, for the three calls that cannot have one:
/// asking whether a sign-in is needed, signing in, and refreshing. Separate from
/// apiClientProvider, which needs a session and would therefore be a circle.
final anonymousApiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(baseUrl: ref.watch(serverUrlProvider)),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return ApiClient(
    baseUrl: ref.watch(serverUrlProvider),
    familyId: prefs.getString(familyIdKey),
    caregiverId: prefs.getString(caregiverIdKey),
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
    await _authenticate(() => _anonymous.signIn(providerToken));
  }

  Future<void> signInWithPassword(String email, String password) async {
    await _authenticate(() => _anonymous.signInWithPassword(email, password));
  }

  Future<void> signUp(String email, String password, {String? name}) async {
    await _authenticate(() => _anonymous.signUp(email, password, name: name));
  }

  Future<void> _authenticate(Future<Session> Function() call) async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _remember(await call()));
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

/// The family's reminder rules. Invalidate after adding, toggling or removing one.
final routinesProvider = FutureProvider<List<Routine>>(
  (ref) => ref.watch(apiClientProvider).listRoutines(),
);

/// Notes between caregivers. Only meaningful when signed in (there has to be someone
/// to send to), so it stays empty when the server asks nobody to sign in.
final messagesProvider = FutureProvider<List<Message>>((ref) async {
  if (ref.watch(sessionProvider).value == null) return const <Message>[];
  return ref.watch(apiClientProvider).messages();
});

/// How many notes the other parent has left that this one has not read yet.
final unreadMessagesProvider = Provider<int>((ref) {
  final messages = ref.watch(messagesProvider).value ?? const <Message>[];
  return messages.where((m) => !m.mine && !m.read).length;
});

/// Everyone in this family, by id. A server that asks nobody to sign in has nobody in
/// it, and then no record has an author -- which is honest, so it simply shows none.
final familyMembersProvider = FutureProvider<Map<String, AuthUser>>((ref) async {
  if (ref.watch(sessionProvider).value == null) return const {};
  final members = await ref.watch(apiClientProvider).familyMembers();
  return {for (final member in members) member.id: member};
});

/// Everyone on the family, id -> name, so a record's created_by becomes "Dad" on the
/// other phone even with nobody signed in. Includes the account-less caregivers.
final caregiversProvider = FutureProvider<Map<String, String>>((ref) async {
  if (ref.watch(familyIdProvider) == null) return const {};
  try {
    final list = await ref.watch(apiClientProvider).caregivers();
    return {for (final c in list) c.id: c.name};
  } catch (_) {
    return const {};
  }
});

/// This device's own caregiver id (no-auth) or signed-in user id, so its own logs carry
/// no "who" label.
final myLoggerIdProvider = Provider<String?>((ref) =>
    ref.watch(sharedPrefsProvider).getString(caregiverIdKey) ??
    ref.watch(sessionProvider).value?.user.id);

/// What to call whoever logged a record: nothing if it was you (you know), and the other
/// caregiver's name if it was not. Two people half asleep at 3am need to know which of
/// them already did it.
final loggedByProvider = Provider.family<String?, String?>((ref, userId) {
  if (userId == null || userId == ref.watch(myLoggerIdProvider)) return null;
  final name = ref.watch(caregiversProvider).value?[userId];
  if (name != null) return name;
  final member = ref.watch(familyMembersProvider).value?[userId];
  return member?.name ?? member?.email ?? 'Someone else';
});

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

final intentBridgeProvider = Provider<IntentBridge>((ref) => const IntentBridge());

/// A tick that goes up each time the Action button or Siri asks to start a voice log. The
/// shell switches to the Log tab on it; the log screen opens the mic. It is a counter, not
/// a bool, so pressing the button twice in a row is two separate requests.
class VoiceLaunchNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final voiceLaunchProvider =
    NotifierProvider<VoiceLaunchNotifier, int>(VoiceLaunchNotifier.new);

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
        wsBaseUrl: wsFromHttp(ref.watch(serverUrlProvider)),
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

/// The charts. Invalidated on every save and on the other parent's, like the timeline:
/// a chart that does not move when you log something is a chart nobody trusts.
final statsProvider = FutureProvider.family<Stats, String>(
  (ref, babyId) => ref.watch(apiClientProvider).stats(babyId: babyId),
);

/// A tick every 30s, so "N ago" text and the fill-toward-next bars on the dashboard
/// keep moving without a save or a pull-to-refresh. Watching it is enough to rebuild.
final dashboardClockProvider = StreamProvider<DateTime>(
  (ref) => Stream<DateTime>.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  ),
);

/// Next-up predictions and the week's trends. Invalidated on every save: logging a
/// feed moves the next-feed estimate.
final insightsProvider = FutureProvider.family<Insights, String>(
  (ref, babyId) => ref.watch(apiClientProvider).insights(
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

/// The languages this caregiver speaks. Sent with every utterance, so that what comes
/// back is in one of them and never in a language nobody in the house has ever spoken.
class SpokenLanguagesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final saved = ref.watch(sharedPrefsProvider).getStringList(spokenLanguagesKey);
    return (saved == null || saved.isEmpty) ? kDefaultLanguages : saved;
  }

  /// Never empty: an empty list is not "no preference", it is "any language on earth",
  /// which is the thing this setting exists to rule out.
  Future<void> set(List<String> codes) async {
    final next = codes.where(kLanguages.containsKey).toList();
    if (next.isEmpty) return;
    await ref.read(sharedPrefsProvider).setStringList(spokenLanguagesKey, next);
    state = next;

    // Dayby cannot answer in a language you have just said you do not speak.
    if (!next.contains(ref.read(assistantLangProvider))) {
      await ref.read(assistantLangProvider.notifier).set(next.first);
    }
  }
}

final spokenLanguagesProvider =
    NotifierProvider<SpokenLanguagesNotifier, List<String>>(SpokenLanguagesNotifier.new);

/// The language the assistant speaks back in, for the surfaces where nobody has said
/// anything for it to detect: the tips on Home and the wrapped story. What the caregiver
/// *says* is worked out from the words themselves. Defaults to Korean.
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

/// Light, dark, or whatever the phone is set to. Defaults to the phone.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.watch(sharedPrefsProvider).getString(themeModeKey);
    return ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> set(ThemeMode mode) async {
    await ref.read(sharedPrefsProvider).setString(themeModeKey, mode.name);
    state = mode;
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

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
