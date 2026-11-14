import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/message.dart';

/// Offline-first storage for chat (Hive).
///
/// Two responsibilities:
///   • cache  — the last messages per conversation, so opening a chat offline
///              shows the real history instead of a spinner.
///   • outbox — messages the server has not accepted yet, so a send is never
///              silently lost when the connection drops.
class ChatLocalStore {
  ChatLocalStore._(this._cache, this._outbox);

  static const _cacheBox = 'chat_messages';
  static const _outboxBox = 'chat_outbox';
  static const int maxCachedPerConversation = 120;

  static final _log = AppLogger('chat.store');

  final Box<String> _cache;
  final Box<String> _outbox;

  static ChatLocalStore? _instance;
  static ChatLocalStore? get instance => _instance;

  /// Must be called once at boot. Failure is reported, never fatal: without
  /// Hive the app still works online, it just loses the cache.
  static Future<void> open() async {
    if (_instance != null) return;
    try {
      await Hive.initFlutter();
      final cache = await Hive.openBox<String>(_cacheBox);
      final outbox = await Hive.openBox<String>(_outboxBox);
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
    final tail = messages.length > maxCachedPerConversation
        ? messages.sublist(messages.length - maxCachedPerConversation)
        : messages;
    _cache.put(conversationId, jsonEncode(tail.map((m) => m.toMap()).toList()));
  }

  List<Message> cachedMessages(String conversationId) {
    final raw = _cache.get(conversationId);
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
      _cache.delete(conversationId);
      return const [];
    }
  }

  void clearCache(String conversationId) => _cache.delete(conversationId);

  // ----------------------------------------------------------------- outbox
  void enqueue(PendingMessage message) =>
      _outbox.put(message.clientId, jsonEncode(message.toMap()));

  List<PendingMessage> pending() {
    final items = <PendingMessage>[];
    for (final key in _outbox.keys) {
      final raw = _outbox.get(key);
      if (raw == null) continue;
      try {
        items.add(
          PendingMessage.fromMap(jsonDecode(raw) as Map<String, dynamic>),
        );
      } catch (_) {
        _outbox.delete(key);
      }
    }
    items.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return items;
  }

  List<PendingMessage> pendingFor(String conversationId) =>
      pending().where((p) => p.conversationId == conversationId).toList();

  void dequeue(String clientId) => _outbox.delete(clientId);

  Future<void> clear() async {
    await _cache.clear();
    await _outbox.clear();
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
