import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(familyProvider);
    final babies = ref.watch(babiesProvider);
    final activeId = ref.watch(activeBabyProvider)?.id;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
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
                    subtitle: b.birthdate == null
                        ? null
                        : Text('Born ${formatDate(b.birthdate!)}'),
                    trailing: b.id == activeId
                        ? Icon(Icons.check, color: scheme.primary)
                        : null,
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
            onTap: () => _addBaby(context, ref),
          ),
          const Divider(height: 32),
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('Reset app', style: TextStyle(color: scheme.error)),
            subtitle: const Text('Forget this family on this device'),
            onTap: () => _confirmReset(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _addBaby(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddBabySheet(),
    );
    if (added == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Baby added')));
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
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
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

class _AddBabySheet extends ConsumerStatefulWidget {
  const _AddBabySheet();

  @override
  ConsumerState<_AddBabySheet> createState() => _AddBabySheetState();
}

class _AddBabySheetState extends ConsumerState<_AddBabySheet> {
  final _name = TextEditingController();
  String? _sex;
  DateTime? _birthdate;
  bool _saving = false;

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
    setState(() => _saving = true);
    try {
      final baby = await ref.read(apiClientProvider).addBaby(
            name: name,
            sex: _sex,
            birthdate: _birthdate,
          );
      ref.invalidate(babiesProvider);
      await ref.read(selectedBabyIdProvider.notifier).set(baby.id);
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not add: $e')));
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
          Text('Add a baby', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
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
                : const Text('Add'),
          ),
        ],
      ),
    );
  }
}
