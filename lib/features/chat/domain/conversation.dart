import 'message.dart';

/// The other participant in a direct chat, as much as the list needs.
class ChatPeer {
  const ChatPeer({
    required this.id,
    required this.displayName,
    this.username,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String? username;
  final String? avatarUrl;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters1;
    return '${parts.first.characters1}${parts.last.characters1}';
  }

  factory ChatPeer.fromMap(Map<String, dynamic> map) => ChatPeer(
    id: map['id'] as String,
    displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
        ? map['display_name'] as String
        : 'Pulse user',
    username: map['username'] as String?,
    avatarUrl: map['avatar_url'] as String?,
  );
}

extension on String {
  String get characters1 => isEmpty ? '?' : substring(0, 1).toUpperCase();
}

class Conversation {
  const Conversation({
    required this.id,
    required this.peer,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageSenderId,
    this.unreadCount = 0,
  });

  final String id;
  final ChatPeer peer;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final String? lastMessageSenderId;
  final int unreadCount;

  bool get hasUnread => unreadCount > 0;

  /// True when the newest visible message is mine (drives the "You: " prefix).
  bool isMineLast(String myId) => lastMessageSenderId == myId;

  factory Conversation.fromMap(
    Map<String, dynamic> map, {
    required String myId,
  }) {
    final members = (map['conversation_members'] as List<dynamic>? ?? const []);
    final other = members
        .cast<Map<String, dynamic>>()
        .map((m) => m['profiles'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .where((p) => p['id'] != myId)
        .toList();
    final lastAt = map['last_message_at'] as String?;
    return Conversation(
      id: map['id'] as String,
      peer: other.isEmpty
          ? const ChatPeer(id: '', displayName: 'Pulse user')
          : ChatPeer.fromMap(other.first),
      lastMessageAt: lastAt == null ? null : DateTime.parse(lastAt).toLocal(),
      lastMessagePreview: map['last_message_preview'] as String?,
      lastMessageSenderId: map['last_message_sender'] as String?,
    );
  }
}

/// A conversation plus its locally cached messages.
class ConversationThread {
  const ConversationThread({
    required this.conversation,
    required this.messages,
  });

  final Conversation conversation;
  final List<Message> messages;
}
