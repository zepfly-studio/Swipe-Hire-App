import 'package:flutter/foundation.dart';
import '../models/pair/chat_models.dart';
import '../models/pair/pair_person.dart';
import 'api_client.dart';
import 'polling.dart';
import 'visible_poller.dart';

/// The company <-> candidate pair chat (backend `/chats`, both roles).
class PairChatService {
  PairChatService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final PairChatService instance = PairChatService._internal();

  @visibleForTesting
  factory PairChatService.test(ApiClient api) => PairChatService._internal(api: api);

  final ApiClient _api;

  static String _enc(String id) => Uri.encodeComponent(id);

  List<Map<String, dynamic>> _rows(Map<String, dynamic> res, String key) => [
        for (final e in (res[key] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];

  Future<List<PairConversation>> conversations() async {
    final res = await _api.get('/chats');
    return _rows(res, 'conversations').map(PairConversation.fromMap).toList();
  }

  Future<List<PairContact>> contacts() async {
    final res = await _api.get('/chats/contacts');
    return _rows(res, 'contacts').map(PairContact.fromMap).toList();
  }

  Future<int> unreadCount() async {
    final res = await _api.get('/chats/unread-count');
    return pairInt(res['count']);
  }

  /// Last 200 messages, oldest first. The server marks the other side's
  /// messages read as a side effect.
  Future<PairThread> thread(String otherId) async {
    final res = await _api.get('/chats/${_enc(otherId)}');
    return PairThread.fromMap(res, fallbackId: otherId);
  }

  Future<PairMessage> send(String otherId, String text) async {
    final res = await _api.post('/chats/${_enc(otherId)}', body: {'text': text});
    final message = res['message'];
    DataRefresh.instance.bump();
    if (message is Map) return PairMessage.fromMap(Map<String, dynamic>.from(message));
    return PairMessage(id: '', text: text, mine: true, at: DateTime.now());
  }

  /// Company only: one message to up to 50 candidates.
  Future<BulkSendResult> sendBulk(List<String> candidateIds, String text) async {
    final res = await _api.post('/chats/bulk', body: {'text': text, 'candidateIds': candidateIds});
    DataRefresh.instance.bump();
    return BulkSendResult.fromMap(res);
  }
}

/// The unread-messages number for the bottom-nav badge: polls
/// `GET /chats/unread-count` every 15 s while at least one badge is on
/// screen, and on demand ([refresh]).
class ChatUnreadPoller {
  ChatUnreadPoller._();
  static final ChatUnreadPoller instance = ChatUnreadPoller._();

  final ValueNotifier<int> count = ValueNotifier<int>(0);

  int _refs = 0;
  VisiblePoller? _poller;

  /// A badge that shows [count] calls this when it mounts.
  void acquire() {
    _refs++;
    if (_refs == 1) {
      _poller = VisiblePoller(interval: const Duration(seconds: 15), onTick: refresh)..start();
    }
  }

  void release() {
    if (_refs == 0) return;
    _refs--;
    if (_refs == 0) {
      _poller?.dispose();
      _poller = null;
    }
  }

  Future<void> refresh() async {
    try {
      count.value = await PairChatService.instance.unreadCount();
    } catch (_) {
      // Keep the last known value.
    }
  }
}
