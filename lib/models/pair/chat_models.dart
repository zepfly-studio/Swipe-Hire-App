import 'pair_person.dart';

/// One row of `GET /chats`.
class PairConversation {
  final PairPerson person;
  final String stage;
  final String lastText;
  final DateTime? lastAt;
  final bool lastMine;
  final int unread;
  final DateTime? updatedAt;

  const PairConversation({
    required this.person,
    this.stage = '',
    this.lastText = '',
    this.lastAt,
    this.lastMine = false,
    this.unread = 0,
    this.updatedAt,
  });

  factory PairConversation.fromMap(Map<String, dynamic> m) {
    final last = pairMap(m['lastMessage']);
    return PairConversation(
      person: PairPerson.fromMap(m),
      stage: pairStr(m['stage']),
      lastText: pairStr(last['text']),
      lastAt: pairDate(last['at']),
      lastMine: last['mine'] == true,
      unread: pairInt(m['unread']),
      updatedAt: pairDate(m['updatedAt']),
    );
  }

  PairConversation withUnread(int n) => PairConversation(
        person: person,
        stage: stage,
        lastText: lastText,
        lastAt: lastAt,
        lastMine: lastMine,
        unread: n,
        updatedAt: updatedAt,
      );
}

/// One row of `GET /chats/contacts` (people you may start a chat with).
class PairContact {
  final PairPerson person;
  final String stage;
  final bool hasChat;
  final DateTime? updatedAt;

  const PairContact({required this.person, this.stage = '', this.hasChat = false, this.updatedAt});

  factory PairContact.fromMap(Map<String, dynamic> m) => PairContact(
        person: PairPerson.fromMap(m),
        stage: pairStr(m['stage']),
        hasChat: m['hasChat'] == true,
        updatedAt: pairDate(m['updatedAt']),
      );
}

/// A chat bubble. [pending] is a local optimistic message not yet confirmed.
class PairMessage {
  final String id;
  final String text;
  final bool mine;
  final DateTime? at;
  final bool read;
  final bool pending;

  const PairMessage({
    required this.id,
    required this.text,
    required this.mine,
    this.at,
    this.read = false,
    this.pending = false,
  });

  factory PairMessage.fromMap(Map<String, dynamic> m) => PairMessage(
        id: pairStr(m['id']),
        text: pairStr(m['text']),
        mine: m['mine'] == true,
        at: pairDate(m['at']),
        read: m['read'] == true,
      );
}

class PairThread {
  final PairPerson person;
  final List<PairMessage> messages;
  const PairThread({required this.person, required this.messages});

  factory PairThread.fromMap(Map<String, dynamic> m, {String fallbackId = ''}) {
    final withMap = pairMap(m['with']);
    if (pairStr(withMap['id']).isEmpty) withMap['id'] = fallbackId;
    return PairThread(
      person: PairPerson.fromMap(withMap),
      messages: [
        for (final e in (m['messages'] as List? ?? const []))
          if (e is Map) PairMessage.fromMap(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

class BulkSendResult {
  final int sent;
  final List<String> skipped;
  const BulkSendResult({this.sent = 0, this.skipped = const []});

  factory BulkSendResult.fromMap(Map<String, dynamic> m) => BulkSendResult(
        sent: pairInt(m['sent']),
        skipped: [for (final e in (m['skipped'] as List? ?? const [])) e.toString()],
      );
}

/// Whether [a] and [b] fall on the same local calendar day.
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// For the thread view: entry `i` is true when message `i` starts a new
/// calendar day (first message, or its day differs from the previous one).
List<bool> dayBreaks(List<PairMessage> messages) {
  final out = <bool>[];
  DateTime? prev;
  for (final m in messages) {
    final at = m.at;
    if (at == null) {
      out.add(false);
      continue;
    }
    out.add(prev == null || !sameDay(prev, at));
    prev = at;
  }
  return out;
}
