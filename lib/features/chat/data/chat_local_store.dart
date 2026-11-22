import 'dart:async';
import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/message.dart';
import 'encrypted_chat_boxes.dart';
import 'hive_message_sync_store.dart';

/// Offline-first storage for chat (Hive).
///
/// Two responsibilities:
///   • cache  — the last messages per conversation, so opening a chat offline
///              shows the real history instead of a spinner.
///   • outbox — messages the server has not accepted yet, so a send is never
///              silently lost when the connection drops.
class ChatLocalStore {
  ChatLocalStore._(this._cache, this._outbox, [this._owner]);

  /// For local tests with disposable Hive boxes; never pass production data.
  ChatLocalStore.forTesting(Box<String> cache, Box<String> outbox)
    : this._(cache, outbox);

  static const int maxCachedPerConversation = 120;

  static final _log = AppLogger('chat.store');

  final Box<String> _cache;
  final Box<String> _outbox;
  final String? _owner;

  /// Journal snapshots live in the same encrypted box as chat cache entries.
  HiveMessageSyncStore get journalStore => HiveMessageSyncStore(_cache);

  /// Bind every operation to the authenticated account. Legacy unscoped data
  /// is intentionally left untouched: it has no trustworthy owner metadata.
  ChatLocalStore forUser(String userId) {
    if (userId.trim().isEmpty) throw ArgumentError('userId is required');
    return ChatLocalStore._(_cache, _outbox, userId);
  }

  String get _prefix {
    final owner = _owner;
    if (owner == null) throw StateError('Chat store requires an account scope');
    return 'v2:${base64Url.encode(utf8.encode(owner))}:';
  }

  String _key(String id) => '$_prefix${base64Url.encode(utf8.encode(id))}';

  static ChatLocalStore? _instance;
  static ChatLocalStore? get instance => _instance;

  /// Must be called once at boot. Failure is reported, never fatal: without
  /// Hive the app still works online, it just loses the cache.
  static Future<void> open() async {
    if (_instance != null) return;
    try {
      await Hive.initFlutter();
      final boxes = await openEncryptedChatBoxes(const PlatformChatKeyVault());
      final cache = boxes.cache;
      final outbox = boxes.outbox;
      _instance = ChatLocalStore._(cache, outbox);
      _log.info(
        'chat_store_ready',
        data: {'cached': cache.length, 'queued': outbox.length},
      );
    } catch (e) {
      _log.error('chat_store_open_failed', error: e);
    }
  }

  // ------------------------------------------------------------------ cache
  void cacheMessages(String conversationId, List<Message> messages) {
    // Pending/failed rows live in the outbox. Message serialization does not
    // encode local delivery state, so caching them here would turn them into
    // false "sent" messages on the next launch.
    final confirmed = messages
        .where((m) => m.delivery == DeliveryState.sent)
        .toList();
    final tail = confirmed.length > maxCachedPerConversation
        ? confirmed.sublist(confirmed.length - maxCachedPerConversation)
        : confirmed;
    try {
      unawaited(
        _cache
            .put(
              _key(conversationId),
              jsonEncode(tail.map((m) => m.toMap()).toList()),
            )
            .catchError((Object _) {
              _log.warning('chat_cache_write_failed');
            }),
      );
    } catch (_) {
      _log.warning('chat_cache_write_failed');
    }
  }

  List<Message> cachedMessages(String conversationId) {
    final raw = _cache.get(_key(conversationId));
    if (raw == null) return const [];
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Message.fromMap)
          .toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } catch (e) {
      _log.warning(
        'chat_cache_corrupt',
        data: {'conversation': conversationId},
      );
      // Retain corrupt material for non-destructive recovery; never expose it.

      return const [];
    }
  }

  Future<void> clearCache(String conversationId) =>
      _cache.delete(_key(conversationId));

  // ----------------------------------------------------------------- outbox
  Future<void> enqueue(PendingMessage message) async {
    await _outbox.put(_key(message.clientId), jsonEncode(message.toMap()));
    await _outbox.flush();
  }

  List<PendingMessage> pending() {
    final items = <PendingMessage>[];
    final prefix = _prefix;
    for (final key in _outbox.keys) {
      if (key is! String || !key.startsWith(prefix)) continue;
      final raw = _outbox.get(key);
      if (raw == null) continue;
      try {
        items.add(
          PendingMessage.fromMap(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        // Do not delete or replay corrupt drafts; preserve for recovery.
        _log.warning('chat_outbox_corrupt');
      }
    }
    items.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return items;
  }

  List<PendingMessage> pendingFor(String conversationId) =>
      pending().where((p) => p.conversationId == conversationId).toList();

  Future<void> dequeue(String clientId) => _outbox.delete(_key(clientId));

  /// Delete an outbox entry only after seeing a server-confirmed row with the
  /// same owner, conversation, client id and text. A collision is not proof.
  Future<int> reconcileConfirmed(Iterable<Message> confirmed) async {
    final owner = _owner;
    if (owner == null) throw StateError('Chat store requires an account scope');
    var removed = 0;
    for (final message in confirmed) {
      final id = message.clientId;
      if (id == null ||
          message.delivery != DeliveryState.sent ||
          message.senderId != owner ||
          message.kind != MessageKind.text) {
        continue;
      }
      final raw = _outbox.get(_key(id));
      if (raw == null) continue;
      PendingMessage item;
      try {
        item = PendingMessage.fromMap(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _log.warning('chat_outbox_corrupt');
        continue;
      }
      if (item.clientId != id ||
          message.conversationId != item.conversationId ||
          message.body != item.body) {
        continue;
      }
      await dequeue(item.clientId);
      removed++;
    }
    return removed;
  }

  /// Reconcile an ownerless legacy queue entry only against a confirmed server
  /// row from this account with an exact client id, conversation and body. This
  /// is evidence that it was already sent, not proof of ownership for an
  /// unsent draft. Unmatched or malformed entries remain untouched and hidden.
  Future<int> reconcileLegacyConfirmed(Iterable<Message> confirmed) async {
    final owner = _owner;
    if (owner == null) throw StateError('Chat store requires an account scope');
    var removed = 0;
    for (final message in confirmed) {
      final id = message.clientId;
      if (id == null ||
          id.startsWith('v2:') ||
          message.senderId != owner ||
          message.delivery != DeliveryState.sent ||
          message.kind != MessageKind.text) {
        continue;
      }
      final raw = _outbox.get(id);
      if (raw == null) continue;
      try {
        final pending = PendingMessage.fromMap(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (pending.clientId != id ||
            pending.conversationId != message.conversationId ||
            pending.body != message.body) {
          continue;
        }
        // Never remove a newly changed value following the read above.
        if (_outbox.get(id) != raw) continue;
        await _outbox.delete(id);
        await _outbox.flush();
        removed++;
      } catch (_) {
        _log.warning('legacy_outbox_reconciliation_failed');
      }
    }
    return removed;
  }

  /// Clear only this account, never another account or unowned legacy data.
  Future<void> clear() async {
    final prefix = _prefix;
    final journalPrefix = 'sync:v1:${base64Url.encode(utf8.encode(_owner!))}:';
    final quarantinePrefix =
        'sync_quarantine:v1:${base64Url.encode(utf8.encode(_owner))}:';
    await _cache.deleteAll(
      _cache.keys
          .whereType<String>()
          .where(
            (k) =>
                k.startsWith(prefix) ||
                k.startsWith(journalPrefix) ||
                k.startsWith(quarantinePrefix),
          )
          .toList(),
    );
    await _outbox.deleteAll(
      _outbox.keys
          .whereType<String>()
          .where((k) => k.startsWith(prefix))
          .toList(),
    );
  }
}

/// A message waiting to reach the server.
class PendingMessage {
  const PendingMessage({
    required this.clientId,
    required this.conversationId,
    required this.body,
    required this.queuedAt,
  });

  final String clientId;
  final String conversationId;
  final String body;
  final DateTime queuedAt;

  Map<String, dynamic> toMap() => {
    'client_id': clientId,
    'conversation_id': conversationId,
    'body': body,
    'queued_at': queuedAt.toUtc().toIso8601String(),
  };

  factory PendingMessage.fromMap(Map<String, dynamic> map) => PendingMessage(
    clientId: map['client_id'] as String,
    conversationId: map['conversation_id'] as String,
    body: map['body'] as String,
    queuedAt: DateTime.parse(map['queued_at'] as String),
  );
}
