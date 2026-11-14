import 'conversation.dart';
import 'message.dart';

/// Everything the chat UI needs from storage. Implemented by the Supabase
/// repository; the offline cache and outbox sit in front of it.
abstract interface class ChatRepository {
  /// Conversations for the signed-in user, newest activity first.
  Future<List<Conversation>> conversations();

  /// Current messages in a conversation, oldest first.
  Future<List<Message>> messages(String conversationId, {int limit = 100});

  /// Creates the direct conversation for [otherUserId] if it does not exist and
  /// returns its id. Idempotent server-side.
  Future<String> startDirectConversation(String otherUserId);

  /// Sends a message. [clientId] is the idempotency key: retrying with the same
  /// value can never create a duplicate.
  Future<Message> sendMessage({
    required String conversationId,
    required String clientId,
    required String body,
    MessageKind kind = MessageKind.text,
    String? mediaUrl,
    int? mediaBytes,
    int? durationMs,
  });

  /// Soft-deletes one of my own messages.
  Future<void> deleteMessage(String messageId);

  /// Marks the conversation as read up to now.
  Future<void> markRead(String conversationId);

  /// Server-side inserts for a conversation (Realtime).
  Stream<Message> newMessages(String conversationId);

  /// Ephemeral typing signals (Realtime broadcast, not persisted).
  Stream<bool> typingSignals(String conversationId);

  /// Announces that I am typing. Throttled by the caller to one signal per 3s.
  Future<void> broadcastTyping(String conversationId);

  /// People I can start a chat with (everyone but me, for now).
  Future<List<ChatPeerSummary>> people();
}

class ChatPeerSummary {
  const ChatPeerSummary({
    required this.id,
    required this.displayName,
    this.username,
  });

  final String id;
  final String displayName;
  final String? username;
}
