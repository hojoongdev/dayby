import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/event.dart';
import '../providers.dart';
import '../units.dart';
import '../widgets/event_tile.dart';
import '../widgets/glass.dart';

/// How far back the records list reaches. The recent-100 default could only ever show
/// today; a caregiver looking back over a week or a month needs the window they picked.
enum _Range { day, week, month, all }

class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key});

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  _Range _range = _Range.week;
  String? _type; // null = all categories
  DateTime _day = DateTime.now(); // the chosen day, in Day mode

  /// The [from, to) the records come from, quantised to whole days so the fetch key is
  /// stable across rebuilds (a live `now` in the key would refetch on every frame).
  (DateTime, DateTime) _window() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    switch (_range) {
      case _Range.day:
        final s = DateTime(_day.year, _day.month, _day.day);
        return (s, s.add(const Duration(days: 1)));
      case _Range.week:
        return (startOfToday.subtract(const Duration(days: 6)), endOfToday);
      case _Range.month:
        return (startOfToday.subtract(const Duration(days: 29)), endOfToday);
      case _Range.all:
        return (DateTime(2015), endOfToday);
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeBabyProvider);
    return Stack(
      children: [
        const Positioned.fill(child: GlassBackground()),
        SafeArea(
          child: active == null
              ? const Center(child: Text('Add a baby in Settings first.'))
              : _body(active.id),
        ),
      ],
    );
  }

  Widget _body(String babyId) {
    final (from, to) = _window();
    final events =
        ref.watch(rangeEventsProvider((babyId: babyId, from: from, to: to)));
    return Column(
      children: [
        _RangeBar(
          range: _range,
          day: _day,
          onRange: (r) => setState(() => _range = r),
          onPickDay: _pickDay,
        ),
        Expanded(
          child: events.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Could not load the records: $e')),
            data: (all) {
              final types = {for (final e in all) e.type}.toList()..sort();
              final filtered =
                  all.where((e) => _type == null || e.type == _type).toList();
              return Column(
                children: [
                  _TypeBar(
                    types: types,
                    type: _type,
                    onType: (t) => setState(() => _type = t),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(rangeEventsProvider(
                            (babyId: babyId, from: from, to: to)));
                        await ref.read(rangeEventsProvider(
                                (babyId: babyId, from: from, to: to))
                            .future);
                      },
                      child: filtered.isEmpty
                          ? _Scrollable(
                              child: Text(all.isEmpty
                                  ? 'Nothing logged in this range.'
                                  : 'No records match this filter.'),
                            )
                          : _EventList(filtered),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The range switch, plus the day chip when a single day is chosen.
class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.range,
    required this.day,
    required this.onRange,
    required this.onPickDay,
  });

  final _Range range;
  final DateTime day;
  final ValueChanged<_Range> onRange;
  final VoidCallback onPickDay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<_Range>(
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(value: _Range.day, label: Text('Day')),
                ButtonSegment(value: _Range.week, label: Text('Week')),
                ButtonSegment(value: _Range.month, label: Text('Month')),
                ButtonSegment(value: _Range.all, label: Text('All')),
              ],
              selected: {range},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onRange(s.first),
            ),
          ),
          if (range == _Range.day) ...[
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.event_outlined, size: 18),
              label: Text(formatDate(day)),
              onPressed: onPickDay,
            ),
          ],
        ],
      ),
    );
  }
}

/// The category filter chips, built from the types actually present in the range.
class _TypeBar extends StatelessWidget {
  const _TypeBar({required this.types, required this.type, required this.onType});

  final List<String> types;
  final String? type;
  final ValueChanged<String?> onType;

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(context, 'All', type == null, () => onType(null)),
          for (final t in types)
            _chip(context, _cap(t), type == t, () => onType(t)),
        ],
      ),
    );
  }

  Widget _chip(
      BuildContext context, String label, bool selected, VoidCallback onTap) {
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
    ref.invalidate(rangeEventsProvider);
    ref.invalidate(tipsProvider(event.babyId));
    ref.invalidate(statsProvider(event.babyId));
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
