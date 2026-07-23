/// A note the model drafted from an utterance ("tell mum to buy diapers"), for the app
/// to confirm and send.
class MessageDraft {
  const MessageDraft({this.to, required this.text});

  final String? to;
  final String text;

  factory MessageDraft.fromJson(Map<String, dynamic> json) => MessageDraft(
        to: json['to'] as String?,
        text: json['text'] as String,
      );
}

/// A note between caregivers, as the thread shows it.
class Message {
  const Message({
    required this.id,
    required this.text,
    this.fromName,
    this.mine = false,
    this.read = false,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String? fromName;
  final bool mine;
  final bool read;
  final DateTime createdAt;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        text: json['text'] as String,
        fromName: json['from_name'] as String?,
        mine: json['mine'] as bool? ?? false,
        read: json['read'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
