import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/routine.dart';
import '../providers.dart';
import '../widgets/glass.dart';

/// The event types a rule can fire after, with how they read in a sentence.
const _triggers = {
  'feeding': 'a feeding',
  'diaper': 'a diaper change',
  'sleep': 'a sleep',
  'bath': 'a bath',
  'medicine': 'medicine',
  'pumping': 'pumping',
};

String _describe(Routine r) {
  if (r.kind == RoutineKind.daily) return 'Every day at ${r.timeLocal}';
  final after = _triggers[r.triggerType] ?? r.triggerType ?? 'an event';
  final delay = r.delayMin ?? 0;
  return delay > 0 ? 'After $after, $delay min later' : 'After $after';
}

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final routines = ref.watch(routinesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Reminders'),
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSheet(context, ref),
        icon: const Icon(Icons.add_alarm),
        label: const Text('Add'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: routines.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load reminders: $e')),
              data: (rules) => rules.isEmpty
                  ? _empty(theme)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                          child: Text(
                            'Rules run on your phone, even with Dayby closed.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        for (final r in rules) _RuleTile(r),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.alarm_add_outlined,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'No reminders yet.\nAdd one like "after a feeding, give vitamin D".',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );

  Future<void> _addSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _RoutineForm(),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile(this.rule);

  final Routine rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(rule.id),
        direction: DismissDirection.endToStart,
        background: _deleteBackground(theme),
        confirmDismiss: (_) => _confirmDelete(context),
        onDismissed: (_) async {
          await ref.read(apiClientProvider).deleteRoutine(rule.id);
          ref.invalidate(routinesProvider);
        },
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rule.message, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(_describe(rule),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(
                value: rule.active,
                onChanged: (on) async {
                  await ref.read(apiClientProvider).setRoutineActive(rule.id, on);
                  ref.invalidate(routinesProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deleteBackground(ThemeData theme) => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      );

  Future<bool> _confirmDelete(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this reminder?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return yes ?? false;
  }
}

class _RoutineForm extends ConsumerStatefulWidget {
  const _RoutineForm();

  @override
  ConsumerState<_RoutineForm> createState() => _RoutineFormState();
}

class _RoutineFormState extends ConsumerState<_RoutineForm> {
  final _message = TextEditingController();
  RoutineKind _kind = RoutineKind.afterEvent;
  String _trigger = 'feeding';
  int _delay = 30;
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String get _timeLocal =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'What should the reminder say?');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).createRoutine(
            kind: _kind,
            message: message,
            triggerType: _kind == RoutineKind.afterEvent ? _trigger : null,
            delayMin: _kind == RoutineKind.afterEvent ? _delay : null,
            timeLocal: _kind == RoutineKind.daily ? _timeLocal : null,
          );
      ref.invalidate(routinesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New reminder', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<RoutineKind>(
                segments: const [
                  ButtonSegment(
                      value: RoutineKind.afterEvent, label: Text('After an event')),
                  ButtonSegment(value: RoutineKind.daily, label: Text('Every day')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 16),
              if (_kind == RoutineKind.afterEvent) ..._afterFields(theme) else _dailyField(theme),
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reminder',
                  hintText: 'Give vitamin D',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _afterFields(ThemeData theme) => [
        DropdownButtonFormField<String>(
          initialValue: _trigger,
          decoration: const InputDecoration(
              labelText: 'After', border: OutlineInputBorder()),
          items: [
            for (final e in _triggers.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => _trigger = v ?? 'feeding'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Remind', style: theme.textTheme.bodyLarge),
            Expanded(
              child: Slider(
                value: _delay.toDouble(),
                min: 0,
                max: 120,
                divisions: 24,
                label: '$_delay min',
                onChanged: (v) => setState(() => _delay = v.round()),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text('$_delay min later', style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ];

  Widget _dailyField(ThemeData theme) => Row(
        children: [
          Text('At', style: theme.textTheme.bodyLarge),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final picked =
                  await showTimePicker(context: context, initialTime: _time);
              if (picked != null) setState(() => _time = picked);
            },
            icon: const Icon(Icons.schedule),
            label: Text(_time.format(context)),
          ),
        ],
      );
}
