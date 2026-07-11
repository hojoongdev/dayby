class Event {
  const Event({
    required this.id,
    required this.babyId,
    required this.type,
    this.subtype,
    this.fields = const {},
    required this.time,
    this.note,
    this.source,
    required this.createdAt,
  });

  final String id;
  final String babyId;
  final String type;
  final String? subtype;
  final Map<String, dynamic> fields;
  final DateTime time;
  final String? note;
  final String? source;
  final DateTime createdAt;

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'] as String,
        babyId: json['baby_id'] as String,
        type: json['type'] as String,
        subtype: json['subtype'] as String?,
        fields: (json['fields'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        time: DateTime.parse(json['time'] as String),
        note: json['note'] as String?,
        source: json['source'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class StructuredEvent {
  const StructuredEvent({
    required this.type,
    this.subtype,
    this.fields = const {},
    this.time,
    this.note,
    this.confidence = 'medium',
  });

  final String type;
  final String? subtype;
  final Map<String, dynamic> fields;
  final DateTime? time;
  final String? note;
  final String confidence;

  factory StructuredEvent.fromJson(Map<String, dynamic> json) =>
      StructuredEvent(
        type: json['type'] as String,
        subtype: json['subtype'] as String?,
        fields: (json['fields'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
        time: json['time'] == null
            ? null
            : DateTime.parse(json['time'] as String),
        note: json['note'] as String?,
        confidence: json['confidence'] as String? ?? 'medium',
      );
}

class StructuredResult {
  const StructuredResult({
    this.action = 'create',
    this.babyRef,
    this.events = const [],
    this.needsClarification,
    this.lang = 'ko',
  });

  final String action;
  final String? babyRef;
  final List<StructuredEvent> events;
  final String? needsClarification;
  final String lang;

  factory StructuredResult.fromJson(Map<String, dynamic> json) =>
      StructuredResult(
        action: json['action'] as String? ?? 'create',
        babyRef: json['baby_ref'] as String?,
        events: (json['events'] as List? ?? const [])
            .map((e) => StructuredEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        needsClarification: json['needs_clarification'] as String?,
        lang: json['lang'] as String? ?? 'ko',
      );
}
