/// A reminder rule a family set for itself: fire after an event, or at a daily time.
enum RoutineKind { afterEvent, daily }

RoutineKind _kindFrom(String raw) =>
    raw == 'daily' ? RoutineKind.daily : RoutineKind.afterEvent;

String kindToWire(RoutineKind kind) =>
    kind == RoutineKind.daily ? 'daily' : 'after_event';

class Routine {
  const Routine({
    required this.id,
    required this.kind,
    required this.message,
    this.triggerType,
    this.delayMin,
    this.timeLocal,
    this.active = true,
    this.babyId,
  });

  final String id;
  final RoutineKind kind;
  final String message;

  /// after_event: which event type to fire after, and how long after it.
  final String? triggerType;
  final int? delayMin;

  /// daily: the time of day on the caregiver's clock, "HH:MM".
  final String? timeLocal;

  final bool active;
  final String? babyId;

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
        id: json['id'] as String,
        kind: _kindFrom(json['kind'] as String),
        message: json['message'] as String,
        triggerType: json['trigger_type'] as String?,
        delayMin: json['delay_min'] as int?,
        timeLocal: json['time_local'] as String?,
        active: json['active'] as bool? ?? true,
        babyId: json['baby_id'] as String?,
      );
}
