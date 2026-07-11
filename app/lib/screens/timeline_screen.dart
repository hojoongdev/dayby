import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/event.dart';
import '../providers.dart';
import '../widgets/event_tile.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBabyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: active == null
          ? const Center(child: Text('Add a baby in Settings first.'))
          : _Timeline(babyId: active.id),
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.babyId});

  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider(babyId));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(eventsProvider(babyId));
        await ref.read(eventsProvider(babyId).future);
      },
      child: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Scrollable(
          child: Text('Could not load the timeline: $e'),
        ),
        data: (list) => list.isEmpty
            ? const _Scrollable(
                child: Text('No events yet. Log something in the Log tab.'),
              )
            : _EventList(list),
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList(this.events);

  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
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
        return EventTile(row as Event);
      },
    );
  }
}

/// A scrollable wrapper so short states still trigger pull-to-refresh.
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
