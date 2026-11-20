import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/chat_repository.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';

/// PostgREST + Realtime implementation. Every error is mapped to a typed failure
/// so the UI never shows a raw exception (§11).
class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('chat');

  final SupabaseClient _client;
  final AppLogger _log;

  String get _me {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        'Session expired. Please sign in again.',
        kind: AuthFailureKind.notConfigured,
      );
    }
    return user.id;
  }

  @override
  Future<List<Conversation>> conversations() async {
    final me = _me;
    try {
      final rows = await _client
          .from('conversations')
          .select(
            'id, kind, title, last_message_at, last_message_preview, last_message_sender, '
            'conversation_members(user_id, role, last_read_at, '
            'profiles(id, display_name, username, avatar_url, photo_visible))',
          )
          .order('last_message_at', ascending: false, nullsFirst: false);
      return rows
          .map((r) => Conversation.fromMap(r, myId: me))
          .where((c) => c.isGroup || c.peer.id.isNotEmpty)
          .toList();
    } on PostgrestException catch (e) {
      throw _map(e, 'conversations');
    }
  }

  @override
  Future<List<Message>> messages(
    String conversationId, {
    int limit = 100,
  }) async {
    try {
      final rows = await _client
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(limit);
      final list = rows.map(Message.fromMap).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } on PostgrestException catch (e) {
      throw _map(e, 'messages');
    }
  }

  @override
  Future<String> startDirectConversation(String otherUserId) async {
    try {
      final result = await _client.rpc(
        'start_direct_conversation',
        params: {'p_other': otherUserId},
      );
      if (result is String) return result;
      return result.toString();
    } on PostgrestException catch (e) {
      throw switch (e.code) {
        '23503' => const ValidationFailure(
          'peer',
          'That person no longer has a Pulse account.',
        ),
        '22023' => const ValidationFailure(
          'peer',
          'Pick someone else to chat with.',
        ),
        '28000' => const AuthFailure('Please sign in again.'),
        _ => _map(e, 'start_conversation'),
      };
    }
  }

  @override
  Future<Message> sendMessage({
    required String conversationId,
    required String clientId,
    required String body,
    MessageKind kind = MessageKind.text,
    String? mediaUrl,
    String? mediaName,
    int? mediaBytes,
    int? durationMs,
  }) async {
    // Media messages carry a URL instead of body text; text messages must not
    // be blank.
    if (kind == MessageKind.text) {
      final reason = Message.validateBody(body);
      if (reason != null) throw ValidationFailure('body', reason);
    } else if (mediaUrl == null || mediaUrl.isEmpty) {
      throw const ValidationFailure('media', 'Upload finished without a URL.');
    }
    try {
      final row = await _client
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': _me,
            'kind': messageKindToDb(kind),
            'body': kind == MessageKind.text ? body.trim() : null,
            'media_url': mediaUrl,
            'media_name': mediaName,
            'media_bytes': mediaBytes,
            'duration_ms': durationMs,
            'client_id': clientId,
          })
          .select()
          .single();
      return Message.fromMap(row);
    } on PostgrestException catch (e) {
      // 23505 on (conversation_id, client_id) means the outbox retried a row the
      // server already stored — fetch it instead of failing the send.
      if (e.code == '23505') {
        final existing = await _client
            .from('messages')
            .select()
            .eq('conversation_id', conversationId)
            .eq('client_id', clientId)
            .maybeSingle();
        if (existing != null) return Message.fromMap(existing);
      }
      throw _map(e, 'send_message');
    }
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    try {
      await _client
          .from('messages')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', messageId);
    } on PostgrestException catch (e) {
      throw _map(e, 'delete_message');
    }
  }

  @override
  Future<void> markRead(String conversationId) async {
    try {
      await _client
          .from('conversation_members')
          .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('conversation_id', conversationId)
          .eq('user_id', _me);
    } on PostgrestException catch (e) {
      // Read receipts are cosmetic; never surface this as a send failure.
      _log.warning('mark_read_failed', data: {'code': e.code});
    }
  }

  @override
  Stream<Message> newMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .map((rows) => rows.map(Message.fromMap).toList())
        .expand((list) => list.where((m) => m.delivery == DeliveryState.sent))
        .handleError((Object e) {
          _log.warning('realtime_messages_error');
        });
  }

  @override
  Stream<bool> typingSignals(String conversationId) {
    final controller = StreamController<bool>.broadcast();
    final channel = _client.channel('typing:$conversationId');
    channel
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final from = payload['payload']?['user_id']?.toString();
            if (from != null && from != _me && !controller.isClosed) {
              controller.add(true);
            }
          },
        )
        .subscribe();
    controller.onCancel = () async {
      await _client.removeChannel(channel);
      if (!controller.isClosed) await controller.close();
    };
    return controller.stream;
  }

  @override
  Future<void> broadcastTyping(String conversationId) async {
    try {
      final channel = _client.channel('typing:$conversationId');
      channel.subscribe();
      await channel.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': _me},
      );
      await _client.removeChannel(channel);
    } catch (e) {
      _log.warning('typing_broadcast_failed');
    }
  }

  @override
  Future<List<ChatPeerSummary>> people() async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, display_name, username, avatar_url, photo_visible')
          .neq('id', _me)
          .order('display_name')
          .limit(100);
      return rows
          .map(
            (r) => ChatPeerSummary(
              id: r['id'] as String,
              displayName:
                  (r['display_name'] as String?)?.trim().isNotEmpty == true
                  ? r['display_name'] as String
                  : 'Pulse user',
              username: r['username'] as String?,
              // Hidden means hidden, here too.
              avatarUrl: r['photo_visible'] == false
                  ? null
                  : r['avatar_url'] as String?,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw _map(e, 'people');
    }
  }

  @override
  Future<ConversationStats> stats(String conversationId) async {
    try {
      final all = await _client
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .count(CountOption.exact);
      final media = await _client
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('kind', 'text')
          .count(CountOption.exact);
      return ConversationStats(messages: all.count, media: media.count);
    } on PostgrestException catch (e) {
      throw _map(e, 'stats');
    }
  }

  // ------------------------------------------------------------------ groups
  static const _groupErrorCodes = {
    'not_a_member',
    'not_allowed',
    'owner_only',
    'invalid_title',
    'member_not_found',
    'group_full',
  };

  @override
  Future<String> createGroup({
    required String title,
    required List<String> memberIds,
  }) async {
    try {
      final result = await _client.rpc(
        'create_group',
        params: {'p_title': title, 'p_members': memberIds},
      );
      return result as String;
    } on PostgrestException catch (e) {
      throw _map(e, 'createGroup');
    }
  }

  @override
  Future<List<GroupMember>> groupMembers(String conversationId) async {
    try {
      final rows = await _client
          .from('conversation_members')
          .select('user_id, role, profiles(id, display_name, username)')
          .eq('conversation_id', conversationId);
      final members = rows.map((r) {
        final profile = r['profiles'] as Map<String, dynamic>?;
        final name = (profile?['display_name'] as String?)?.trim();
        return GroupMember(
          userId: r['user_id'] as String,
          displayName: name?.isNotEmpty == true ? name! : 'Pulse user',
          username: profile?['username'] as String?,
          role: GroupRole.parse(r['role'] as String?),
        );
      }).toList();
      members.sort((a, b) {
        int rank(GroupRole? r) => switch (r) {
          GroupRole.owner => 0,
          GroupRole.admin => 1,
          _ => 2,
        };
        final byRole = rank(a.role).compareTo(rank(b.role));
        return byRole != 0
            ? byRole
            : a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              );
      });
      return members;
    } on PostgrestException catch (e) {
      throw _map(e, 'groupMembers');
    }
  }

  @override
  Future<void> addGroupMember(String conversationId, String userId) =>
      _groupRpc('add_group_member', 'addGroupMember', {
        'p_conversation': conversationId,
        'p_user': userId,
      });

  @override
  Future<void> removeGroupMember(String conversationId, String userId) =>
      _groupRpc('remove_group_member', 'removeGroupMember', {
        'p_conversation': conversationId,
        'p_user': userId,
      });

  @override
  Future<void> setGroupRole(
    String conversationId,
    String userId,
    GroupRole role,
  ) => _groupRpc('set_group_role', 'setGroupRole', {
    'p_conversation': conversationId,
    'p_user': userId,
    'p_role': role.name,
  });

  @override
  Future<void> renameGroup(String conversationId, String title) => _groupRpc(
    'rename_group',
    'renameGroup',
    {'p_conversation': conversationId, 'p_title': title},
  );

  @override
  Future<void> leaveGroup(String conversationId) => _groupRpc(
    'leave_group',
    'leaveGroup',
    {'p_conversation': conversationId},
  );

  Future<void> _groupRpc(
    String fn,
    String op,
    Map<String, dynamic> params,
  ) async {
    try {
      await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw _map(e, op);
    }
  }

  AppFailure _map(PostgrestException e, String op) {
    _log.warning(op, error: '${e.code}');
    final text = e.message.toLowerCase();
    final reason = _groupErrorCodes.firstWhere(
      (code) => text.contains(code),
      orElse: () => '',
    );
    if (reason.isNotEmpty) {
      return ServerFailure(safeCode: reason, statusCode: 403);
    }
    if (text.contains('socket') ||
        text.contains('connection') ||
        text.contains('host lookup')) {
      return NetworkFailure(detail: '${e.code}: ${e.message}');
    }
    return switch (e.code) {
      // The database's own refuse-to-write signal (migrations/0016). It is not
      // a retryable error: the account is on hold and the app has to say so.
      'PULSE' => const AccountSuspendedFailure(),
      '42501' => const ServerFailure(statusCode: 403, safeCode: 'not_allowed'),
      '23505' => const ServerFailure(safeCode: 'duplicate'),
      'PGRST116' => const ServerFailure(safeCode: 'not_found'),
      _ => ServerFailure(safeCode: e.code ?? 'chat_error'),
    };
  }
}
