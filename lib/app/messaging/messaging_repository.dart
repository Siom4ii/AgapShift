import 'messaging_models.dart';

/// Direct messages between users (Supabase or local mock KV).
abstract class MessagingRepository {
  Future<List<DmConversationSummary>> listConversations();

  /// Returns existing 1:1 thread id or creates a new one.
  Future<String> getOrCreateConversation({required String otherUserId});

  Future<List<DmMessage>> listMessages(String conversationId, {int limit = 200});

  Future<DmMessage> sendMessage({
    required String conversationId,
    required String body,
  });

  /// Live updates for a thread (Supabase realtime; mock polls).
  Stream<List<DmMessage>> watchMessages(String conversationId);

  Future<void> markConversationRead(String conversationId);
}
