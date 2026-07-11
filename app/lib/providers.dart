import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_client.dart';
import 'models/event.dart';
import 'models/family.dart';

const familyIdKey = 'family_id';
const selectedBabyIdKey = 'selected_baby_id';

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
}

final familyIdProvider =
    NotifierProvider<FamilyIdNotifier, String?>(FamilyIdNotifier.new);

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
