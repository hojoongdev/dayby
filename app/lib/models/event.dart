import 'message.dart';

export 'message.dart' show MessageDraft, Message;

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
    this.createdBy,
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

  /// Which parent logged it. Null on a server that asks nobody to sign in.
  final String? createdBy;
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
        createdBy: json['created_by'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// One line of the chat, as shown on screen. The "saved" lines go too: an event that was
/// offered but never confirmed is not in the timeline, and the model has to tell those apart.
class Turn {
  const Turn({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;

  Map<String, dynamic> toJson() => {
        'role': fromUser ? 'user' : 'assistant',
        'text': text,
      };
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

/// What comes back from a recording: what the server heard, and what it made of it. The
/// transcript is what goes in the chat bubble — with the server transcribing, it is the
/// first sight the caregiver gets of the words that were understood.
class IngestVoiceResult {
  const IngestVoiceResult({required this.transcript, required this.result});

  final String transcript;
  final StructuredResult result;

  factory IngestVoiceResult.fromJson(Map<String, dynamic> json) => IngestVoiceResult(
        transcript: json['transcript'] as String,
        result: StructuredResult.fromJson(json['result'] as Map<String, dynamic>),
      );
}

/// What comes back from a photo: where it was stored, and what the model made of it.
/// The photo id is already inside every event's `fields`, so saving keeps them together.
class IngestPhotoResult {
  const IngestPhotoResult({required this.photoId, required this.result});

  final String photoId;
  final StructuredResult result;

  factory IngestPhotoResult.fromJson(Map<String, dynamic> json) =>
      IngestPhotoResult(
        photoId: json['photo_id'] as String,
        result: StructuredResult.fromJson(json['result'] as Map<String, dynamic>),
      );
}

/// A reminder rule the caregiver stated out loud, for the app to confirm and save.
class RoutineSpec {
  const RoutineSpec({
    required this.kind,
    required this.message,
    this.triggerType,
    this.delayMin,
    this.timeLocal,
  });

  final String kind; // "after_event" | "daily"
  final String message;
  final String? triggerType;
  final int? delayMin;
  final String? timeLocal;

  factory RoutineSpec.fromJson(Map<String, dynamic> json) => RoutineSpec(
        kind: json['kind'] as String,
        message: json['message'] as String,
        triggerType: json['trigger_type'] as String?,
        delayMin: (json['delay_min'] as num?)?.toInt(),
        timeLocal: json['time_local'] as String?,
      );
}

class ReminderSpec {
  const ReminderSpec({required this.message, required this.at, this.target = const []});

  final String message;
  final DateTime at;

  /// Caregiver names or relations the reminder is for; empty means everyone.
  final List<String> target;

  factory ReminderSpec.fromJson(Map<String, dynamic> json) => ReminderSpec(
        message: json['message'] as String,
        at: DateTime.parse(json['at'] as String),
        target: (json['target'] as List? ?? const []).cast<String>(),
      );
}

class StructuredResult {
  const StructuredResult({
    this.action = 'create',
    this.babyRef,
    this.events = const [],
    this.target,
    this.needsClarification,
    this.reply,
    this.settings,
    this.routine,
    this.reminder,
    this.message,
    this.lang = 'ko',
  });

  final String action;
  final String? babyRef;
  final List<StructuredEvent> events;

  /// For a correction or a removal: the record the server found in the real
  /// timeline. Null means it could not tell which one was meant — and then nothing
  /// is offered, because the wrong guess would be applied to a real record.
  final Event? target;

  final String? needsClarification;

  /// A short spoken confirmation the model wrote in the caller's language.
  final String? reply;

  /// A settings change requested by voice, e.g. {"temp": "f"}.
  final Map<String, dynamic>? settings;

  /// A reminder rule the caregiver set up by voice, for the app to confirm and save.
  final RoutineSpec? routine;

  /// A one-off reminder at a set time, possibly for the other caregiver.
  final ReminderSpec? reminder;

  /// A note to the other caregiver, drafted by voice, for the app to confirm and send.
  final MessageDraft? message;
  final String lang;

  bool get isUpdate => action == 'update';
  bool get isDelete => action == 'delete';

  factory StructuredResult.fromJson(Map<String, dynamic> json) =>
      StructuredResult(
        action: json['action'] as String? ?? 'create',
        babyRef: json['baby_ref'] as String?,
        events: (json['events'] as List? ?? const [])
            .map((e) => StructuredEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        target: json['target'] == null
            ? null
            : Event.fromJson(json['target'] as Map<String, dynamic>),
        needsClarification: json['needs_clarification'] as String?,
        reply: json['reply'] as String?,
        settings: (json['settings'] as Map?)?.cast<String, dynamic>(),
        routine: json['routine'] == null
            ? null
            : RoutineSpec.fromJson(json['routine'] as Map<String, dynamic>),
        reminder: json['reminder'] == null
            ? null
            : ReminderSpec.fromJson(json['reminder'] as Map<String, dynamic>),
        message: json['message'] == null
            ? null
            : MessageDraft.fromJson(json['message'] as Map<String, dynamic>),
        lang: json['lang'] as String? ?? 'ko',
      );
}
