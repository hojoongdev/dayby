import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../charts/palette.dart';
import '../format.dart';
import '../models/event.dart';
import '../models/family.dart';
import '../models/insights.dart';
import '../providers.dart';
import '../units.dart';
import '../widgets/assistant_card.dart';
import '../widgets/dash_card.dart';
import '../widgets/glass.dart';
import '../widgets/insights_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBabyProvider);
    // No app bar of its own: the shell owns the top bar and the tab switch.
    return Stack(
      children: [
        const Positioned.fill(child: GlassBackground()),
        SafeArea(
          child: active == null
              ? const Center(child: Text('Add a baby in Settings to begin.'))
              : _Board(baby: active),
        ),
      ],
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.baby});

  final Baby baby;

  Event? _lastOf(List<Event> events, String type) {
    for (final e in events) {
      if (e.type == type) return e;
    }
    return null;
  }

  DateTime? _nextOf(Insights? insights, String type) {
    if (insights == null) return null;
    for (final p in insights.predictions) {
      if (p.type == type) return p.at;
    }
    return null;
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(eventsProvider(baby.id));
    ref.invalidate(insightsProvider(baby.id));
    ref.invalidate(tipsProvider(baby.id));
    ref.invalidate(statsProvider(baby.id));
  }

  /// One-tap log, with a line to say it landed and a way to take it back — a silent
  /// write reads as a dead button.
  Future<void> _quickLog(
    WidgetRef ref, BuildContext context, String type, {String? subtype}) async {
    final messenger = ScaffoldMessenger.of(context);
    final units = ref.read(unitPrefsProvider);
    try {
      final saved = await ref.read(apiClientProvider).createEvent(
            babyId: baby.id,
            type: type,
            subtype: subtype,
            source: 'text',
          );
      _refresh(ref);
      messenger.showSnackBar(SnackBar(
        content: Text(
            'Logged ${eventSummary(saved.type, saved.subtype, saved.fields, units: units)}'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await ref.read(apiClientProvider).deleteEvent(saved.id);
            _refresh(ref);
          },
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  /// Tapping sleep is a toggle: if she is asleep, this is the wake-up; if she is up,
  /// she is going down. The server computes the nap length from the pair.
  Future<void> _toggleSleep(WidgetRef ref, BuildContext context, Event? lastSleep) {
    final ending = lastSleep?.subtype == 'start';
    return _quickLog(ref, context, 'sleep', subtype: ending ? 'end' : 'start');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild every 30s so "N ago" and the progress bars keep moving on their own.
    ref.watch(dashboardClockProvider);
    final events = ref.watch(eventsProvider(baby.id)).value ?? const <Event>[];
    final insights = ref.watch(insightsProvider(baby.id)).value;
    final units = ref.watch(unitPrefsProvider);
    final ink = ChartInk.of(context);

    final feeding = _lastOf(events, 'feeding');
    final diaper = _lastOf(events, 'diaper');
    final sleep = _lastOf(events, 'sleep');

    final cards = <Widget>[
      DashCard(
        icon: Icons.local_drink_outlined,
        accent: ink.feeding,
        detail: _detail(feeding, units),
        sinceLabel: 'since feeding',
        at: feeding?.time,
        nextAt: _nextOf(insights, 'feeding'),
        onAdd: () => _quickLog(ref, context, 'feeding', subtype: feeding?.subtype),
      ),
      DashCard(
        icon: Icons.child_care_outlined,
        accent: ink.diaper,
        detail: _detail(diaper, units),
        sinceLabel: 'since last change',
        at: diaper?.time,
        nextAt: _nextOf(insights, 'diaper'),
        onAdd: () => _quickLog(ref, context, 'diaper', subtype: diaper?.subtype ?? 'wet'),
      ),
      DashCard(
        icon: Icons.bedtime_outlined,
        accent: ink.sleep,
        detail: _sleepDetail(sleep, units),
        sinceLabel: 'since sleep',
        at: sleep?.time,
        // Asleep right now: the headline is how long she has been down, not "N ago".
        headlineOverride: sleep?.subtype == 'start' && sleep != null
            ? formatMinutes(DateTime.now().difference(sleep.time).inMinutes)
            : null,
        onAdd: () => _toggleSleep(ref, context, sleep),
      ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(eventsProvider(baby.id));
        ref.invalidate(insightsProvider(baby.id));
        ref.invalidate(tipsProvider(baby.id));
        await ref.read(eventsProvider(baby.id).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _Header(baby: baby),
          const SizedBox(height: 8),
          AssistantCard(babyId: baby.id),
          ...cards,
          const SizedBox(height: 4),
          _QuickRow(onLog: (type, subtype) => _quickLog(ref, context, type, subtype: subtype)),
          const SizedBox(height: 12),
          InsightsCard(babyId: baby.id),
        ],
      ),
    );
  }
}

String _sleepDetail(Event? sleep, UnitPrefs units) {
  if (sleep == null) return 'Not logged yet';
  if (sleep.subtype == 'start') return 'Asleep';
  final minutes = sleep.fields['duration_min'];
  if (minutes is num) return 'Slept ${formatMinutes(minutes)}';
  return _detail(sleep, units);
}

String _detail(Event? e, UnitPrefs units) {
  if (e == null) return 'Not logged yet';
  final parts = <String>[];
  if (e.subtype != null && e.subtype!.isNotEmpty) {
    parts.add('${e.subtype![0].toUpperCase()}${e.subtype!.substring(1)}');
  }
  e.fields.forEach((key, value) => parts.add(formatField(key, value, units)));
  return parts.isEmpty
      ? '${e.type[0].toUpperCase()}${e.type.substring(1)}'
      : parts.join(' · ');
}

class _Header extends StatelessWidget {
  const _Header({required this.baby});

  final Baby baby;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = baby.name.isEmpty ? '?' : baby.name[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Text(initial,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(baby.name, style: theme.textTheme.headlineSmall),
          ),
          if (baby.birthdate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('D+${DateTime.now().difference(baby.birthdate!).inDays}',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// The "Other" row: one-tap logging for the things that do not get their own card.
class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.onLog});

  final void Function(String type, String? subtype) onLog;

  static const _items = [
    (icon: Icons.bathtub_outlined, type: 'bath', label: 'Bath'),
    (icon: Icons.medication_outlined, type: 'medicine', label: 'Meds'),
    (icon: Icons.thermostat_outlined, type: 'temperature', label: 'Temp'),
    (icon: Icons.water_drop_outlined, type: 'pumping', label: 'Pump'),
    (icon: Icons.sticky_note_2_outlined, type: 'memo', label: 'Note'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF121821).withValues(alpha: 0.82)
            : Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: (theme.brightness == Brightness.dark ? Colors.white : Colors.black)
              .withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick log',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final item in _items)
                Expanded(
                  child: _QuickButton(
                    icon: item.icon,
                    label: item.label,
                    onTap: () => onLog(item.type, null),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
