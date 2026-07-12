import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/event.dart';
import '../models/family.dart';
import '../providers.dart';
import '../units.dart';
import '../widgets/assistant_card.dart';
import '../widgets/glass.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeBabyProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Dayby'),
        backgroundColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: active == null
                ? const Center(child: Text('Add a baby in Settings to begin.'))
                : _Dashboard(baby: active),
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.baby});

  final Baby baby;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(eventsProvider(baby.id));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(eventsProvider(baby.id));
        ref.invalidate(tipsProvider(baby.id));
        await ref.read(eventsProvider(baby.id).future);
      },
      child: eventsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text('Could not load: $e')),
          ),
        ]),
        data: (events) => _content(context, events),
      ),
    );
  }

  Event? _lastOf(List<Event> events, String type) {
    for (final e in events) {
      if (e.type == type) return e;
    }
    return null;
  }

  Widget _content(BuildContext context, List<Event> events) {
    final theme = Theme.of(context);
    final feeding = _lastOf(events, 'feeding');
    final diaper = _lastOf(events, 'diaper');
    final sleep = _lastOf(events, 'sleep');
    final growth = _lastOf(events, 'growth');
    final todayFeeds =
        events.where((e) => e.type == 'feeding' && isToday(e.time)).length;
    final todayDiapers =
        events.where((e) => e.type == 'diaper' && isToday(e.time)).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(baby.name, style: theme.textTheme.headlineMedium),
              if (baby.birthdate != null)
                Text(formatAge(baby.birthdate!),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        AssistantCard(babyId: baby.id),
        _StatCard(
          icon: Icons.local_drink_outlined,
          label: 'Last feeding',
          event: feeding,
        ),
        _StatCard(
          icon: Icons.baby_changing_station_outlined,
          label: 'Last diaper',
          event: diaper,
        ),
        // A sleep that started and has not ended is a baby who is asleep right now,
        // which is a different thing to know than when she last slept.
        if (sleep?.subtype == 'start')
          _StatCard(
            icon: Icons.bedtime,
            label: 'Asleep for',
            event: sleep,
            value: formatMinutes(DateTime.now().difference(sleep!.time).inMinutes),
          )
        else
          _StatCard(
            icon: Icons.bedtime_outlined,
            label: 'Last sleep',
            event: sleep,
          ),
        GlassCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              _Metric(value: '$todayFeeds', label: 'Feedings today'),
              const SizedBox(width: 12),
              _Metric(value: '$todayDiapers', label: 'Diapers today'),
            ],
          ),
        ),
        if (growth != null)
          _StatCard(
            icon: Icons.straighten_outlined,
            label: 'Latest growth',
            event: growth,
          ),
      ],
    );
  }
}

class _StatCard extends ConsumerWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    this.event,
    this.value,
  });

  final IconData icon;
  final String label;
  final Event? event;

  /// Overrides the usual "N ago" headline, for a card that is about something
  /// still happening rather than something that happened.
  final String? value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final units = ref.watch(unitPrefsProvider);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Icon(icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                if (event == null)
                  Text('Not logged yet', style: theme.textTheme.titleMedium)
                else ...[
                  Text(value ?? formatAgo(event!.time),
                      style: theme.textTheme.titleMedium),
                  Text(
                    eventSummary(event!.type, event!.subtype, event!.fields,
                        units: units),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700)),
          Text(label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
