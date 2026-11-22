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
    // `photo_visible = false` means the photo is not delivered anywhere — the
    // chat list included. The name and the initials still arrive; the picture
    // does not, so hiding it means hiding it.
    avatarUrl: map['photo_visible'] == false
        ? null
        : map['avatar_url'] as String?,
  );
}

extension on String {
  String get characters1 => isEmpty ? '?' : substring(0, 1).toUpperCase();
}

/// My role in a group conversation. Direct chats have no role.
enum GroupRole {
  owner,
  admin,
  member;

  static GroupRole? parse(String? raw) => switch (raw) {
    'owner' => GroupRole.owner,
    'admin' => GroupRole.admin,
    'member' => GroupRole.member,
    _ => null,
  };

  bool get canManageMembers => this == owner || this == admin;
  bool get isOwner => this == owner;

  String get label => switch (this) {
    GroupRole.owner => 'Owner',
    GroupRole.admin => 'Admin',
    GroupRole.member => 'Member',
  };
}

class Conversation {
  const Conversation({
    required this.id,
    required this.peer,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageSenderId,
    this.unreadCount = 0,
    this.kind = 'direct',
    this.title,
    this.groupAvatarUrl,
    this.memberCount = 0,
    this.myRole,
    this.peerLastReadAt,
    this.peerLastReadRevision,
  });

  final String id;
  final ChatPeer peer;

  /// 'direct' or 'group'. Groups carry a title and a member count instead of a
  /// meaningful peer.
  final String kind;
  final String? title;
  final String? groupAvatarUrl;
  final int memberCount;
  final GroupRole? myRole;

  /// When the other participant last read this conversation. The only honest
  /// source of the "seen" tick; null when unknown (groups, or no row yet).
  final DateTime? peerLastReadAt;
  final int? peerLastReadRevision;

  bool get isGroup => kind == 'group';

  /// The picture to show: the group's own, or the other person's.
  String? get avatarUrl => isGroup ? groupAvatarUrl : peer.avatarUrl;

  /// What the list and the chat header show.
  String get displayName => isGroup
      ? (title?.trim().isNotEmpty == true ? title! : 'Group')
      : peer.displayName;

  String get subtitleLabel => isGroup
      ? '$memberCount ${memberCount == 1 ? 'member' : 'members'}'
      : '@${peer.username ?? 'pulse'}';

  String get initials {
    if (!isGroup) return peer.initials;
    final clean = displayName.trim();
    return clean.isEmpty ? '#' : clean[0].toUpperCase();
  }

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
    final members = (map['conversation_members'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final otherMembers = members.where((m) => m['user_id'] != myId).toList();
    final other = otherMembers
        .map((m) => m['profiles'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .toList();
    final lastAt = map['last_message_at'] as String?;
    final mine = members.where((m) => m['user_id'] == myId).firstOrNull;
    final peer = other.isEmpty ? null : other.first;
    // `last_read_at` lives on the member row, not on the nested profile.
    final peerReadRaw = otherMembers.isEmpty
        ? null
        : otherMembers.first['last_read_at'] as String?;
    return Conversation(
      id: map['id'] as String,
      kind: (map['kind'] as String?) ?? 'direct',
      title: map['title'] as String?,
      groupAvatarUrl: map['avatar_url'] as String?,
      memberCount: members.length,
      myRole: GroupRole.parse(mine?['role'] as String?),
      peer: peer == null
          ? const ChatPeer(id: '', displayName: 'Pulse user')
          : ChatPeer.fromMap(peer),
      peerLastReadRevision: otherMembers.isEmpty
          ? null
          : (otherMembers.first['last_read_revision'] as num?)?.toInt(),
      peerLastReadAt: peerReadRaw == null
          ? null
          : DateTime.parse(peerReadRaw).toLocal(),
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
