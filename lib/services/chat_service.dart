import '../models/chat_message.dart';
import 'api_client.dart';
import 'polling.dart';

/// Backend-backed chat tied to one [Opportunity] (`messages` table,
/// `GET/POST /opportunities/:id/messages`) -- once a candidate is
/// shortlisted (or further along), the recruiter and candidate can message
/// each other about that specific role. [streamMessages] polls every couple
/// of seconds (and immediately after a send) so the thread feels live.
class ChatService {
  ChatService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final ChatService instance = ChatService._internal();

  final ApiClient _api;

  Future<List<ChatMessage>> fetchMessages(String opportunityId) async {
    final res = await _api.get('/opportunities/$opportunityId/messages');
    return (res['messages'] as List? ?? const [])
        .map((e) => ChatMessage.fromMap(e['id'] as String, Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Stream<List<ChatMessage>> streamMessages(String opportunityId) {
    return pollingStream(() => fetchMessages(opportunityId), interval: const Duration(seconds: 2));
  }

  /// [senderUid]/[senderName] are kept for call-site compatibility; the
  /// backend stamps the sender from the session.
  Future<void> sendMessage({
    required String opportunityId,
    required String senderUid,
    required String senderName,
    required String text,
  }) async {
    await _api.post('/opportunities/$opportunityId/messages', body: {'text': text});
    DataRefresh.instance.bump();
  }
}
