import '../data/hive_message_sync_store.dart';
import '../domain/message_sync.dart';

/// Returns a complete journal snapshot, never a partial page as if caught up.
abstract interface class ChatJournalSync {
  Future<JournalSnapshot> catchUp(String ownerId, String conversationId);
  Future<void> markRead(String conversationId, int revision);
}

class ChatJournalSyncImpl implements ChatJournalSync {
  ChatJournalSyncImpl(
    this.source,
    this.store, {
    this.pageSize = 100,
    this.maxPages = 20,
    this.markRevision,
  });
  final Future<void> Function(String conversationId, int revision)?
  markRevision;
  final MessageChangeSource source;
  final HiveMessageSyncStore store;
  final int pageSize;
  final int maxPages;

  @override
  Future<JournalSnapshot> catchUp(String ownerId, String conversationId) async {
    // Only malformed local snapshots are quarantined; malformed network pages
    // must not reset a healthy cursor. Unsent drafts live in a separate box.
    await store.quarantineMalformedSnapshot(ownerId, conversationId);
    final complete = await MessageCatchUp(
      source,
      store,
      pageSize: pageSize,
    ).run(ownerId: ownerId, conversationId: conversationId, maxPages: maxPages);
    if (!complete) {
      throw const MessageSyncProtocolException('catch-up incomplete');
    }
    return store.snapshot(ownerId, conversationId);
  }

  @override
  Future<void> markRead(String conversationId, int revision) async {
    final mark = markRevision;
    if (mark == null) throw StateError('revision read receipt not configured');
    await mark(conversationId, revision);
  }
}
