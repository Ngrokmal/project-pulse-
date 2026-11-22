import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../domain/message.dart';
import '../domain/message_sync.dart';

/// Experimental Hive adapter for catch-up, not wired into the app. A cursor and
/// all its confirmed rows are encoded in ONE Hive value, so normal writes never
/// split a cursor and its rows across keys. This is not proof of crash/power-loss
/// atomicity, encryption, multi-isolate safety, or suitability for large chats.
/// A dedicated encrypted box and secure key lifecycle are required for use.
class JournalSnapshot {
  const JournalSnapshot(this.revision, this.messages);
  final int revision;
  final List<Message> messages;
}

class HiveMessageSyncStore implements MessageChangeStore {
  HiveMessageSyncStore(this.box);
  final Box<String> box;

  // Shared among adapters using the same box object in this isolate. Hive
  // itself is not being used as a cross-isolate compare-and-swap primitive.
  static final Expando<Map<String, Future<void>>> _locks = Expando();

  String _key(String owner, String conversation) {
    if (owner.trim().isEmpty || conversation.trim().isEmpty) {
      throw ArgumentError('owner and conversation are required');
    }
    String enc(String value) => base64Url.encode(utf8.encode(value));
    return 'sync:v1:${enc(owner)}:${enc(conversation)}';
  }

  Future<T> _locked<T>(String key, Future<T> Function() action) async {
    final locks = _locks[box] ??= <String, Future<void>>{};
    final previous = locks[key];
    final gate = Completer<void>();
    locks[key] = gate.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      if (identical(locks[key], gate.future)) locks.remove(key);
      gate.complete();
    }
  }

  _Snapshot _read(String key, String conversation) {
    final raw = box.get(key);
    if (raw == null) return _Snapshot(0, {});
    // Corruption must fail closed, never be treated as an empty database.
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1 ||
          data['revision'] is! int ||
          (data['revision'] as int) < 0 ||
          data['messages'] is! List) {
        throw const FormatException('invalid sync snapshot');
      }
      final messages = <String, Message>{};
      for (final row in data['messages'] as List) {
        final message = Message.fromMap(Map<String, dynamic>.from(row as Map));
        if (message.conversationId != conversation ||
            message.id.isEmpty ||
            messages.containsKey(message.id)) {
          throw const FormatException('invalid sync row');
        }
        messages[message.id] = message;
      }
      return _Snapshot(data['revision'] as int, messages);
    } catch (_) {
      throw const FormatException('invalid Hive sync snapshot');
    }
  }

  /// Preserve malformed snapshot bytes before resetting only this journal key.
  /// Does not repair a Hive box that itself cannot be opened. A reset causes
  /// the caller to re-fetch server history, and never touches unsent outbox.
  Future<bool> quarantineMalformedSnapshot(
    String ownerId,
    String conversationId,
  ) {
    final key = _key(ownerId, conversationId);
    return _locked(key, () async {
      final raw = box.get(key);
      if (raw == null) return false;
      try {
        _read(key, conversationId);
        return false;
      } on FormatException {
        final prefix =
            'sync_quarantine:v1:${base64Url.encode(utf8.encode(ownerId))}:${base64Url.encode(utf8.encode(conversationId))}:';
        final quarantine = '$prefix${const Uuid().v4()}';
        await box.put(quarantine, raw);
        await box.flush();
        if (box.get(quarantine) != raw || box.get(key) != raw) {
          throw StateError(
            'Could not safely preserve damaged journal snapshot',
          );
        }
        await box.delete(key);
        await box.flush();
        return true;
      }
    });
  }

  @override
  Future<int> revision(String ownerId, String conversationId) {
    final key = _key(ownerId, conversationId);
    return _locked(key, () async => _read(key, conversationId).revision);
  }

  Future<JournalSnapshot> snapshot(String ownerId, String conversationId) {
    final key = _key(ownerId, conversationId);
    return _locked(key, () async {
      final current = _read(key, conversationId);
      final messages = current.messages.values.toList();
      messages.sort((a, b) {
        final time = a.createdAt.compareTo(b.createdAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
      return JournalSnapshot(current.revision, List.unmodifiable(messages));
    });
  }

  Future<List<Message>> messages(String ownerId, String conversationId) async =>
      (await snapshot(ownerId, conversationId)).messages;

  @override
  Future<bool> applyAtomically({
    required String ownerId,
    required String conversationId,
    required int expectedRevision,
    required List<MessageChange> changes,
  }) {
    final key = _key(ownerId, conversationId);
    return _locked(key, () async {
      final current = _read(key, conversationId);
      if (current.revision != expectedRevision) return false;
      if (changes.isEmpty) throw ArgumentError('empty change batch');
      var revision = expectedRevision;
      final rows = Map<String, Message>.of(current.messages);
      for (final change in changes) {
        if (change.revision != revision + 1) {
          throw const MessageSyncProtocolException('non-contiguous revisions');
        }
        final message = change.message;
        final deletedId = change.deletedId;
        if (message != null) {
          if (message.conversationId != conversationId ||
              message.id.isEmpty ||
              message.delivery != DeliveryState.sent) {
            throw const MessageSyncProtocolException('invalid message');
          }
          rows[message.id] = message;
        } else if (deletedId != null && deletedId.isNotEmpty) {
          rows.remove(deletedId);
        } else {
          throw const MessageSyncProtocolException('invalid change');
        }
        revision = change.revision;
      }
      final encoded = jsonEncode({
        'version': 1,
        'revision': revision,
        'messages': rows.values.map((m) => m.toMap()).toList(),
      });
      await box.put(key, encoded);
      await box.flush();
      return true;
    });
  }
}

class _Snapshot {
  _Snapshot(this.revision, this.messages);
  final int revision;
  final Map<String, Message> messages;
}
