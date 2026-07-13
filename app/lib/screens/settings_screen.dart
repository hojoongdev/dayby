import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../format.dart';
import '../models/family.dart';
import '../providers.dart';
import '../widgets/glass.dart';
import 'wrapped_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(familyProvider);
    final babies = ref.watch(babiesProvider);
    final active = ref.watch(activeBabyProvider);
    final activeId = active?.id;
    final session = ref.watch(sessionProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(children: [
        const Positioned.fill(child: GlassBackground()),
        SafeArea(
          child: ListView(
            children: [
          if (family != null) _FamilyCard(name: family.name, code: family.code),
          const _SectionHeader('Babies'),
          babies.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => ListTile(title: Text('Could not load babies: $e')),
            data: (list) => Column(
              children: [
                for (final b in list)
                  ListTile(
                    leading: const Icon(Icons.child_care_outlined),
                    title: Text(b.name),
                    subtitle: Text(_babySubtitle(b)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (b.id == activeId)
                          Icon(Icons.check, color: scheme.primary),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () => _babyForm(context, ref, baby: b),
                        ),
                      ],
                    ),
                    selected: b.id == activeId,
                    onTap: () =>
                        ref.read(selectedBabyIdProvider.notifier).set(b.id),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add a baby'),
            onTap: () => _babyForm(context, ref),
          ),
          if (active != null) ...[
            const _SectionHeader('Keepsake'),
            ListTile(
              leading: const Icon(Icons.auto_stories_outlined),
              title: Text('Your story with ${active.name}'),
              subtitle: const Text('Everything you ever logged, counted'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WrappedScreen(baby: active),
                ),
              ),
            ),
          ],
          const _SectionHeader('Assistant'),
          const _AssistantSection(),
          const _SectionHeader('Units'),
          const _UnitsSection(),
          // Offered only where there is a sensor to ask.
          if (ref.watch(biometricsAvailableProvider).value ?? false) ...[
            const _SectionHeader('Privacy'),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Lock Dayby'),
              subtitle: const Text('Ask for Face ID or a fingerprint to open'),
              value: ref.watch(appLockEnabledProvider),
              onChanged: (on) async {
                await ref.read(appLockEnabledProvider.notifier).set(on);
                // They are already here and already themselves: turning the lock on
                // must not lock them out of the screen they turned it on from.
                if (on) ref.read(unlockedProvider.notifier).unlock();
              },
            ),
          ],
          const Divider(height: 32),
          if (session != null)
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(session.user.email ?? session.user.name ?? 'Signed in'),
              subtitle: const Text('Sign out'),
              trailing: const Icon(Icons.logout),
              onTap: () => ref.read(sessionProvider.notifier).signOut(),
            ),
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('Reset app', style: TextStyle(color: scheme.error)),
            subtitle: const Text('Forget this family on this device'),
            onTap: () => _confirmReset(context, ref),
          ),
            ],
          ),
        ),
      ]),
    );
  }

  String _babySubtitle(Baby b) {
    final parts = <String>[];
    if (b.sex == 'female') parts.add('Girl');
    if (b.sex == 'male') parts.add('Boy');
    if (b.birthdate != null) parts.add(formatAge(b.birthdate!));
    return parts.isEmpty ? 'Tap edit to add details' : parts.join(' · ');
  }

  Future<void> _babyForm(BuildContext context, WidgetRef ref, {Baby? baby}) async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BabyFormSheet(baby: baby),
    );
    if (saved == true) {
      messenger.showSnackBar(SnackBar(
        content: Text(baby == null ? 'Baby added' : 'Baby updated'),
      ));
    }
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset app?'),
        content: const Text(
          'This forgets the family and babies on this device. '
          'Your logged data stays on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.clear();
    ref.read(apiClientProvider).setFamilyId(null);
    ref.invalidate(babiesProvider);
    ref.invalidate(selectedBabyIdProvider);
    await ref.read(familyIdProvider.notifier).clear();
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.name, required this.code});

  final String name;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Invite code', style: theme.textTheme.bodyMedium),
                const SizedBox(width: 12),
                SelectableText(
                  code,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite code copied')),
                    );
                  },
                ),
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.ios_share),
                    tooltip: 'Share',
                    onPressed: () => _share(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The other parent is rarely standing next to you when you set this up, and a code
  /// on its own means nothing to them. Hand the whole invitation to whichever app they
  /// would have been sent it in anyway.
  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Join our family on Dayby',
        text: 'Join our family on Dayby with this invite code: $code',
        // An iPad will not show the sheet unless it is told what it is coming out of.
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }
}

/// The language the assistant answers in where there is nothing to detect it from: the
/// tips on Home, and the wrapped story. What you say to it is always worked out from the
/// words themselves, which is why there is no longer a toggle on the Log tab.
class _AssistantSection extends ConsumerWidget {
  const _AssistantSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _dropdownTile(
      'Language',
      ref.watch(assistantLangProvider),
      const {'ko': 'Korean', 'en': 'English'},
      (v) => ref.read(assistantLangProvider.notifier).set(v),
    );
  }
}

class _UnitsSection extends ConsumerWidget {
  const _UnitsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(unitPrefsProvider);
    final n = ref.read(unitPrefsProvider.notifier);
    return Column(
      children: [
        _dropdownTile('Temperature', u.temp, const {'c': '°C', 'f': '°F'},
            (v) => n.set(temp: v)),
        _dropdownTile('Weight', u.weight, const {'kg': 'kg', 'g': 'g', 'lb': 'lb'},
            (v) => n.set(weight: v)),
        _dropdownTile('Length', u.length, const {'cm': 'cm', 'm': 'm', 'in': 'inch'},
            (v) => n.set(length: v)),
        _dropdownTile('Feeding volume', u.volume, const {'ml': 'ml', 'oz': 'oz'},
            (v) => n.set(volume: v)),
      ],
    );
  }
}

Widget _dropdownTile(String label, String value, Map<String, String> options,
    ValueChanged<String> onChanged) {
  return ListTile(
    title: Text(label),
    trailing: DropdownButton<String>(
      value: value,
      items: [
        for (final e in options.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _BabyFormSheet extends ConsumerStatefulWidget {
  const _BabyFormSheet({this.baby});

  final Baby? baby;

  @override
  ConsumerState<_BabyFormSheet> createState() => _BabyFormSheetState();
}

class _BabyFormSheetState extends ConsumerState<_BabyFormSheet> {
  late final _name = TextEditingController(text: widget.baby?.name ?? '');
  late String? _sex = widget.baby?.sex;
  late DateTime? _birthdate = widget.baby?.birthdate;
  bool _saving = false;

  bool get _isEdit => widget.baby != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthdate = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final api = ref.read(apiClientProvider);
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await api.updateBaby(widget.baby!.id,
            name: name, sex: _sex, birthdate: _birthdate);
      } else {
        final baby =
            await api.addBaby(name: name, sex: _sex, birthdate: _birthdate);
        await ref.read(selectedBabyIdProvider.notifier).set(baby.id);
      }
      ref.invalidate(babiesProvider);
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_isEdit ? 'Edit baby' : 'Add a baby',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _sex,
            decoration: const InputDecoration(labelText: 'Sex (optional)'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Prefer not to say')),
              DropdownMenuItem(value: 'female', child: Text('Girl')),
              DropdownMenuItem(value: 'male', child: Text('Boy')),
            ],
            onChanged: (v) => setState(() => _sex = v),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cake_outlined),
            title: Text(_birthdate == null
                ? 'Birthdate (optional)'
                : formatDate(_birthdate!)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickBirthdate,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }
}
