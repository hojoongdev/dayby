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

class AssistantTips {
  const AssistantTips({
    this.tips = const [],
    this.remindAt,
    this.reminder,
    this.lang = 'en',
  });

  final List<Tip> tips;

  /// When the next gap opens up, and what to say then. Not shown with the others —
  /// this one is handed to the phone, to arrive when nobody is looking at Dayby.
  final DateTime? remindAt;
  final String? reminder;

  /// The language the model wrote in — also the voice TTS should read them with.
  final String lang;

  factory AssistantTips.fromJson(Map<String, dynamic> json) => AssistantTips(
        tips: (json['tips'] as List? ?? const [])
            .map((t) => Tip.fromJson(t as Map<String, dynamic>))
            .toList(),
        remindAt: json['remind_at'] == null
            ? null
            : DateTime.parse(json['remind_at'] as String),
        reminder: json['reminder'] as String?,
        lang: json['lang'] as String? ?? 'en',
      );
}
