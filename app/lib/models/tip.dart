/// One proactive line from the assistant. The server aggregates the facts and the
/// model writes the sentence, so [text] arrives ready to show and to speak.
class Tip {
  const Tip({this.kind = 'tip', this.topic, required this.text});

  /// "nudge" — something looks overdue; "tip" — age-appropriate guidance.
  final String kind;
  final String? topic;
  final String text;

  bool get isNudge => kind == 'nudge';

  factory Tip.fromJson(Map<String, dynamic> json) => Tip(
        kind: json['kind'] as String? ?? 'tip',
        topic: json['topic'] as String?,
        text: json['text'] as String,
      );
}

/// A nudge for later: the overdue-gap one the assistant writes, or a rule the family
/// set. Handed to the phone to arrive when nobody is looking at Dayby.
class ScheduledReminder {
  const ScheduledReminder({required this.at, required this.text});

  final DateTime at;
  final String text;

  factory ScheduledReminder.fromJson(Map<String, dynamic> json) => ScheduledReminder(
        at: DateTime.parse(json['at'] as String),
        text: json['text'] as String,
      );
}

class AssistantTips {
  const AssistantTips({
    this.tips = const [],
    this.scheduled = const [],
    this.lang = 'en',
  });

  final List<Tip> tips;

  /// Everything to leave with the phone. Not shown with the tips above — these arrive
  /// as notifications when nobody is looking at Dayby.
  final List<ScheduledReminder> scheduled;

  /// The language the model wrote in — also the voice TTS should read them with.
  final String lang;

  factory AssistantTips.fromJson(Map<String, dynamic> json) {
    var scheduled = (json['scheduled'] as List? ?? const [])
        .map((s) => ScheduledReminder.fromJson(s as Map<String, dynamic>))
        .toList();
    // An older server sends just the one, in remind_at/reminder.
    if (scheduled.isEmpty && json['remind_at'] != null && json['reminder'] != null) {
      scheduled = [
        ScheduledReminder(
          at: DateTime.parse(json['remind_at'] as String),
          text: json['reminder'] as String,
        ),
      ];
    }
    return AssistantTips(
      tips: (json['tips'] as List? ?? const [])
          .map((t) => Tip.fromJson(t as Map<String, dynamic>))
          .toList(),
      scheduled: scheduled,
      lang: json['lang'] as String? ?? 'en',
    );
  }
}
