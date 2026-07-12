import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'models/event.dart';
import 'models/family.dart';
import 'models/tip.dart';
import 'units.dart';

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

/// The camera / library picker. Behind a provider so a test can hand the screen a
/// picture without opening a platform dialog.
final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

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
        lang: ref.watch(voiceLangProvider),
      ),
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
