import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'models/event.dart';
import 'models/family.dart';

const familyIdKey = 'family_id';
const familyNameKey = 'family_name';
const inviteCodeKey = 'invite_code';
const selectedBabyIdKey = 'selected_baby_id';
const voiceLangKey = 'voice_lang';

final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in main'),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return ApiClient(familyId: prefs.getString(familyIdKey));
});

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

/// Spoken language for voice input ("ko" | "en"). Sets the STT locale and the
/// hint sent to the LLM. Defaults to Korean — Dayby is a Korean-first app.
class VoiceLangNotifier extends Notifier<String> {
  @override
  String build() => ref.watch(sharedPrefsProvider).getString(voiceLangKey) ?? 'ko';

  Future<void> set(String lang) async {
    await ref.read(sharedPrefsProvider).setString(voiceLangKey, lang);
    state = lang;
  }
}

final voiceLangProvider =
    NotifierProvider<VoiceLangNotifier, String>(VoiceLangNotifier.new);
