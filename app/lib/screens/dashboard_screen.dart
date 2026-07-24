import 'package:flutter/cupertino.dart';
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

  /// Quick actions that carry a value (a feed amount, a temperature) ask for it first;
  /// the rest (a bath, a nap toggle) just log. A button that writes a blank record is
  /// worse than no button.
  Future<void> _quickEntry(
      WidgetRef ref, BuildContext context, String type, {String? subtype}) async {
    final units = ref.read(unitPrefsProvider);
    switch (type) {
      case 'feeding':
        final ml = await _askAmount(context, 'Feed amount', units.volume);
        if (ml != null && context.mounted) {
          await _quickLog(ref, context, type,
              subtype: subtype ?? 'bottle', fields: {'amount_ml': ml});
        }
      case 'pumping':
        final ml = await _askAmount(context, 'Pumped', units.volume);
        if (ml != null && context.mounted) {
          await _quickLog(ref, context, type, fields: {'amount_ml': ml});
        }
      case 'temperature':
        final c = await _askTemperature(context, units.temp);
        if (c != null && context.mounted) {
          await _quickLog(ref, context, type, fields: {'temp_c': c});
        }
      case 'diaper':
        final kind = await _askChoice(context, 'Diaper', const ['wet', 'dirty', 'mixed']);
        if (kind != null && context.mounted) {
          await _quickLog(ref, context, type, subtype: kind);
        }
      case 'medicine':
        final name = await _askText(context, 'Medicine', 'e.g. vitamin D');
        if (name != null && context.mounted) {
          await _quickLog(ref, context, type,
              fields: name.isEmpty ? const {} : {'name': name});
        }
      case 'memo':
        final note = await _askText(context, 'Note', 'Anything to remember');
        if (note != null && note.isNotEmpty && context.mounted) {
          await _quickLog(ref, context, type, note: note);
        }
      default:
        await _quickLog(ref, context, type, subtype: subtype);
    }
  }

  /// One-tap log, with a line to say it landed and a way to take it back — a silent
  /// write reads as a dead button.
  Future<void> _quickLog(
    WidgetRef ref,
    BuildContext context,
    String type, {
    String? subtype,
    Map<String, dynamic> fields = const {},
    String? note,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final units = ref.read(unitPrefsProvider);
    try {
      final saved = await ref.read(apiClientProvider).createEvent(
            babyId: baby.id,
            type: type,
            subtype: subtype,
            fields: fields,
            note: note,
            source: 'text',
          );
      _refresh(ref);
      // Tapping sleep twice (down, then up) should not stack two bars that then sit
      // there; the newest replaces the last.
      messenger.hideCurrentSnackBar();
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
        onAdd: () => _quickEntry(ref, context, 'feeding', subtype: feeding?.subtype),
      ),
      DashCard(
        icon: Icons.child_care_outlined,
        accent: ink.diaper,
        detail: _detail(diaper, units),
        sinceLabel: 'since last change',
        at: diaper?.time,
        nextAt: _nextOf(insights, 'diaper'),
        onAdd: () => _quickEntry(ref, context, 'diaper'),
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
        // Clear the floating glass tab bar so the last card is not hidden behind it.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _Header(baby: baby),
          const SizedBox(height: 8),
          AssistantCard(babyId: baby.id),
          ...cards,
          const SizedBox(height: 4),
          _QuickRow(onLog: (type, subtype) => _quickEntry(ref, context, type)),
          const SizedBox(height: 12),
          InsightsCard(babyId: baby.id),
        ],
      ),
    );
  }
}

/// Ask for a volume in the caregiver's unit, return millilitres (what is stored).
/// A feed is a familiar range, not free text — spin a wheel to it. ml 30–300 by 10,
/// or oz 1–10 by a half. Returns ml (what is stored).
Future<double?> _askAmount(BuildContext context, String title, String unit) async {
  final oz = unit == 'oz';
  final values = oz
      ? [for (var v = 1.0; v <= 10.0; v += 0.5) v]
      : [for (var v = 30.0; v <= 300.0; v += 10.0) v];
  final start = () {
    final i = values.indexOf(oz ? 4.0 : 120.0);
    return i < 0 ? values.length ~/ 2 : i;
  }();
  final controller = FixedExtentScrollController(initialItem: start);
  var index = start;

  final picked = await showModalBottomSheet<double>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                SizedBox(
                  height: 180,
                  child: CupertinoPicker(
                    scrollController: controller,
                    itemExtent: 40,
                    onSelectedItemChanged: (i) => index = i,
                    children: [
                      for (final v in values)
                        Center(
                          child: Text(
                            oz ? '$v oz' : '${v.toInt()} ml',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, values[index]),
                        child: const Text('Log'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  controller.dispose();
  if (picked == null) return null;
  return oz ? picked * 29.5735 : picked;
}

/// Ask for a temperature in the caregiver's unit, return Celsius (what is stored).
Future<double?> _askTemperature(BuildContext context, String unit) async {
  final value = await _askNumber(context, 'Temperature', unit == 'f' ? '°F' : '°C');
  if (value == null) return null;
  return unit == 'f' ? (value - 32) * 5 / 9 : value;
}

Future<double?> _askNumber(BuildContext context, String title, String unit) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(suffixText: unit),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log')),
      ],
    ),
  );
  return ok == true ? double.tryParse(controller.text.trim()) : null;
}

Future<String?> _askText(BuildContext context, String title, String hint) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log')),
      ],
    ),
  );
  return ok == true ? controller.text.trim() : null;
}

Future<String?> _askChoice(
    BuildContext context, String title, List<String> options) async {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final option in options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, option),
            child: Text('${option[0].toUpperCase()}${option.substring(1)}'),
          ),
      ],
    ),
  );
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baby.name, style: theme.textTheme.headlineSmall),
                if (baby.birthdate != null)
                  Text(
                    '${formatAge(baby.birthdate!)} '
                    '(D+${DateTime.now().difference(baby.birthdate!).inDays})',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
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
