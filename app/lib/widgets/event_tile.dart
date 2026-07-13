import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format.dart';
import '../models/event.dart';
import '../providers.dart';
import 'photo_thumb.dart';

class EventTile extends ConsumerWidget {
  const EventTile(this.event, {super.key});

  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitPrefsProvider);
    final photoId = event.fields['photo_id'] as String?;
    // Only ever the other parent. You already know which of these were yours; what you
    // are half asleep and wondering at 3am is whether they already did it.
    final loggedBy = ref.watch(loggedByProvider(event.createdBy));
    final note = [?event.note, ?loggedBy].join(' · ');

    return ListTile(
      leading: photoId != null
          ? PhotoThumb(photoId, size: 40)
          : CircleAvatar(child: Icon(_iconFor(event.type))),
      title: Text(eventSummary(event.type, event.subtype, event.fields, units: units)),
      subtitle: note.isEmpty ? null : Text(note),
      trailing: Text(formatClock(event.time)),
    );
  }
}

IconData _iconFor(String type) => switch (type) {
      'feeding' => Icons.local_drink_outlined,
      'sleep' => Icons.bedtime_outlined,
      'diaper' => Icons.baby_changing_station_outlined,
      'bath' => Icons.bathtub_outlined,
      'medicine' => Icons.medication_outlined,
      'temperature' => Icons.thermostat_outlined,
      'pumping' => Icons.water_drop_outlined,
      'growth' => Icons.straighten_outlined,
      'milestone' => Icons.emoji_events_outlined,
      'todo' => Icons.checklist_outlined,
      'appointment' => Icons.event_available_outlined,
      'memo' => Icons.sticky_note_2_outlined,
      _ => Icons.event_note_outlined,
    };
