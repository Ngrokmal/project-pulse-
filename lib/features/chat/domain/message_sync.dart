import 'message.dart';

/// A server-assigned, per-conversation revision. Revisions must be contiguous
/// and assigned in transaction commit order, not from a standalone sequence.
class MessageChange {
  const MessageChange.upsert({
    required this.revision,
    required Message this.message,
  }) : deletedId = null;

  const MessageChange.delete({
    required this.revision,
    required String messageId,
  }) : message = null,
       deletedId = messageId;

  final int revision;
  final Message? message;
  final String? deletedId;
}

/// Fetch committed revisions in order, starting immediately after [after].
/// Empty means caught up for the instant the server read was made, not that a
/// realtime subscription is active. Implementations must not silently omit
/// retained revisions and must fail if the cursor is too old.
abstract interface class MessageChangeSource {
  Future<List<MessageChange>> changes(
    String conversationId,
    int after,
    int limit,
  );
}

/// Durable atomic state boundary. Implementations MUST apply the entire batch
/// and advance its cursor in one transaction, or apply neither. They MUST
/// compare [expectedRevision] against the stored cursor before committing.
abstract interface class MessageChangeStore {
  Future<int> revision(String ownerId, String conversationId);
  Future<bool> applyAtomically({
    required String ownerId,
    required String conversationId,
    required int expectedRevision,
    required List<MessageChange> changes,
  });
}

class MessageSyncProtocolException implements Exception {
  const MessageSyncProtocolException(this.reason);
  final String reason;
  @override
  String toString() => 'MessageSyncProtocolException: $reason';
}

/// A transport-independent catch-up engine. This is not connected to the app:
/// it requires an authorized server revision journal, transactional local
/// storage and reconnect/session integration before it can provide gap safety.
class MessageCatchUp {
  const MessageCatchUp(this.source, this.store, {this.pageSize = 100});
  final MessageChangeSource source;
  final MessageChangeStore store;
  final int pageSize;

  /// Fetch at most [maxPages], so a busy conversation cannot monopolize a
  /// client. False means another catch-up pass is needed. Exceptions preserve
  /// the last successfully committed batch; callers must not mark it caught up.
  Future<bool> run({
    required String ownerId,
    required String conversationId,
    int maxPages = 20,
  }) async {
    if (ownerId.isEmpty ||
        conversationId.isEmpty ||
        pageSize <= 0 ||
        maxPages <= 0) {
      throw ArgumentError(
        'owner, conversation, page size and max pages are required',
      );
    }
    for (var page = 0; page < maxPages; page++) {
      final cursor = await store.revision(ownerId, conversationId);
      if (cursor < 0) {
        throw const MessageSyncProtocolException('invalid cursor');
      }
      final changes = await source.changes(conversationId, cursor, pageSize);
      if (changes.length > pageSize) {
        throw const MessageSyncProtocolException('oversized page');
      }
      if (changes.isEmpty) return true;
      var next = cursor;
      for (final change in changes) {
        if (change.revision != next + 1) {
          throw const MessageSyncProtocolException('non-contiguous revisions');
        }
        if (change.message != null &&
            change.message!.conversationId != conversationId) {
          throw const MessageSyncProtocolException('wrong conversation');
        }
        if (change.deletedId != null && change.deletedId!.isEmpty) {
          throw const MessageSyncProtocolException('invalid deletion');
        }
        next = change.revision;
      }
      final committed = await store.applyAtomically(
        ownerId: ownerId,
        conversationId: conversationId,
        expectedRevision: cursor,
        changes: List.unmodifiable(changes),
      );
      // A competing sync can advance the cursor while the request is in flight.
      // Re-read it and refetch; never apply stale changes over newer state.
      if (!committed) continue;
    }
    return false;
  }
}
