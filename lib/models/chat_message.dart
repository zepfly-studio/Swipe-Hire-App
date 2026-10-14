/// One message in an opportunity's chat thread (backend: `messages` table,
/// `GET/POST /opportunities/:id/messages`) -- the recruiter<->candidate
/// conversation tied to that pipeline entry.
class ChatMessage {
  final String id;
  final String senderUid;
  final String senderName;
  final String text;

  /// "text" for something a person typed; "task" or "interview" for the
  /// automatic messages the task and scheduling flow posts into the thread.
  final String kind;
  final DateTime? sentAt;

  const ChatMessage({
    this.id = '',
    required this.senderUid,
    required this.senderName,
    required this.text,
    this.kind = 'text',
    this.sentAt,
  });

  bool get isSystem => kind != 'text';

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    return ChatMessage(
      id: id,
      senderUid: map['senderUid'] ?? '',
      senderName: map['senderName'] ?? '',
      text: map['text'] ?? '',
      kind: map['kind'] ?? 'text',
      sentAt: DateTime.tryParse(map['sentAt']?.toString() ?? '')?.toLocal(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderUid': senderUid,
      'senderName': senderName,
      'text': text,
      'sentAt': sentAt?.toUtc().toIso8601String(),
    };
  }
}
