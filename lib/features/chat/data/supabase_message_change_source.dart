import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/message.dart';
import '../domain/message_sync.dart';

/// Candidate adapter for the un-deployed journal RPC. It is not registered with
/// the app. Never treat a missing/unauthorized RPC as an empty successful page.
class SupabaseMessageChangeSource implements MessageChangeSource {
  SupabaseMessageChangeSource(
    this.client,
    this.ownerId, {
    this.sessionIsCurrent,
  });
  final SupabaseClient client;
  final String ownerId;
  final bool Function()? sessionIsCurrent;

  void _checkOwner() {
    if (ownerId.isEmpty ||
        client.auth.currentUser?.id != ownerId ||
        (sessionIsCurrent != null && !sessionIsCurrent!())) {
      throw StateError('authenticated account changed');
    }
  }

  Future<void> markReadRevision(String conversationId, int revision) async {
    _checkOwner();
    await client.rpc(
      'pulse_mark_read_revision',
      params: {'p_conversation': conversationId, 'p_revision': revision},
    );
    _checkOwner();
  }

  @override
  Future<List<MessageChange>> changes(
    String conversationId,
    int after,
    int limit,
  ) async {
    _checkOwner();
    final dynamic raw = await client.rpc(
      'pulse_message_changes_since',
      params: {
        'p_conversation': conversationId,
        'p_after': after,
        'p_limit': limit,
      },
    );
    _checkOwner();
    if (raw is! List) throw const FormatException('invalid change page');
    return raw
        .map((entry) {
          if (entry is! Map) throw const FormatException('invalid change');
          final revision = entry['revision'];
          final id = entry['message_id'];
          final payload = entry['message'];
          if (revision is! int ||
              revision <= 0 ||
              revision > 9007199254740991 ||
              id is! String ||
              id.isEmpty) {
            throw const FormatException('invalid change fields');
          }
          if (payload == null) {
            return MessageChange.delete(revision: revision, messageId: id);
          }
          if (payload is! Map) {
            throw const FormatException('invalid message payload');
          }
          final message = Message.fromMap(Map<String, dynamic>.from(payload));
          if (message.id != id || message.conversationId != conversationId) {
            throw const FormatException('message identity mismatch');
          }
          return MessageChange.upsert(revision: revision, message: message);
        })
        .toList(growable: false);
  }
}
