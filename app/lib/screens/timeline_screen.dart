import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/event.dart';
import '../providers.dart';
import '../units.dart';
import '../widgets/event_tile.dart';
import '../widgets/glass.dart';

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  String? _type; // null = all categories
  DateTime? _day; // null = any date

  bool _sameDay(DateTime a, DateTime b) {
    final l = a.toLocal();
    return l.year == b.year && l.month == b.month && l.day == b.day;
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBabyProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Timeline'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: active == null
                ? const Center(child: Text('Add a baby in Settings first.'))
                : _body(active.id),
          ),
        ],
      ),
    );
  }

  Widget _body(String babyId) {
    final events = ref.watch(eventsProvider(babyId));
    return events.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load the timeline: $e')),
      data: (all) {
        final types = {for (final e in all) e.type}.toList()..sort();
        final filtered = all
            .where((e) => _type == null || e.type == _type)
            .where((e) => _day == null || _sameDay(e.time, _day!))
            .toList();
        return Column(
          children: [
            _FilterBar(
              types: types,
              type: _type,
              day: _day,
              onType: (t) => setState(() => _type = t),
              onPickDay: _pickDay,
              onClearDay: () => setState(() => _day = null),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(eventsProvider(babyId));
                  await ref.read(eventsProvider(babyId).future);
                },
                child: filtered.isEmpty
                    ? _Scrollable(
                        child: Text(all.isEmpty
                            ? 'No events yet. Log something in the Log tab.'
                            : 'No events match this filter.'),
                      )
                    : _EventList(filtered),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.types,
    required this.type,
    required this.day,
    required this.onType,
    required this.onPickDay,
    required this.onClearDay,
  });

  final List<String> types;
  final String? type;
  final DateTime? day;
  final ValueChanged<String?> onType;
  final VoidCallback onPickDay;
  final VoidCallback onClearDay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: InputChip(
              avatar: const Icon(Icons.event_outlined, size: 18),
              label: Text(day == null ? 'Any date' : formatDate(day!)),
              onPressed: onPickDay,
              onDeleted: day == null ? null : onClearDay,
            ),
          ),
          _chip(context, 'All', type == null, () => onType(null)),
          for (final t in types)
            _chip(context, _cap(t), type == t, () => onType(t)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _EventList extends ConsumerWidget {
  const _EventList(this.events);

  final List<Event> events;

  /// Swiping is easy to do by accident with a baby in the other arm, so it asks.
  Future<bool> _confirm(BuildContext context, Event event, UnitPrefs units) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this?'),
        content: Text(
          '${eventSummary(event.type, event.subtype, event.fields, units: units)}'
          '\n${formatTime(event.time)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return yes ?? false;
  }

  Future<void> _delete(WidgetRef ref, Event event) async {
    await ref.read(apiClientProvider).deleteEvent(event.id);
    ref.invalidate(eventsProvider(event.babyId));
    ref.invalidate(tipsProvider(event.babyId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final units = ref.watch(unitPrefsProvider);
    final rows = <Object>[];
    String? header;
    for (final e in events) {
      final h = formatDayHeader(e.time, now);
      if (h != header) {
        rows.add(h);
        header = h;
      }
      rows.add(e);
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              row,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          );
        }
        final event = row as Event;
        return Dismissible(
          key: ValueKey(event.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(context).colorScheme.errorContainer,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.onErrorContainer),
          ),
          confirmDismiss: (_) => _confirm(context, event, units),
          onDismissed: (_) => _delete(ref, event),
          child: EventTile(event),
        );
      },
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
          child: Center(child: child),
        ),
      ],
    );
  }
}
