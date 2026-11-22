import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';

/// Experimental mirrored outbox primitive, not wired into the app.
/// Requires independently encrypted Hive boxes and a single owning isolate.
/// A record is written to the mirror and flushed before the primary is changed;
/// tombstones prevent an older replica from resurrecting a deleted message.
class ReplicatedOutbox {
  ReplicatedOutbox(this.primary, this.mirror) {
    if (identical(primary, mirror)) throw ArgumentError('replicas must differ');
  }
  final Box<String> primary;
  final Box<String> mirror;
  static final Expando<Map<String, Future<void>>> _locks = Expando();

  Future<T> _locked<T>(String key, Future<T> Function() action) async {
    final locks = _locks[primary] ??= <String, Future<void>>{};
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

  _Replica? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['version'] != 1 ||
          m['revision'] is! int ||
          (m['revision'] as int) < 1 ||
          m['deleted'] is! bool) {
        throw const FormatException();
      }
      final deleted = m['deleted'] as bool;
      final value = m['value'];
      if ((deleted && value != null) || (!deleted && value is! String)) {
        throw const FormatException();
      }
      return _Replica(m['revision'] as int, deleted, value as String?);
    } catch (_) {
      throw const FormatException('corrupt outbox replica');
    }
  }

  _Replica? _select(String? first, String? second) {
    final a = _decode(first);
    final b = _decode(second);
    if (a == null) return b;
    if (b == null) return a;
    if (a.revision == b.revision &&
        (a.deleted != b.deleted || a.value != b.value)) {
      throw StateError('conflicting outbox replicas');
    }
    return a.revision >= b.revision ? a : b;
  }

  Future<void> _change(String key, String? value) => _locked(key, () async {
    if (key.isEmpty) throw ArgumentError('key required');
    final current = _select(primary.get(key), mirror.get(key));
    final record = _Replica((current?.revision ?? 0) + 1, value == null, value);
    final encoded = record.encode();
    await mirror.put(key, encoded);
    await mirror.flush();
    await primary.put(key, encoded);
    await primary.flush();
  });
  Future<void> put(String key, String value) => _change(key, value);
  Future<void> delete(String key) => _change(key, null);
  Future<String?> get(String key) => _locked(key, () async {
    final current = _select(primary.get(key), mirror.get(key));
    return current == null || current.deleted ? null : current.value;
  });

  /// Repair a missing/stale replica only; a malformed value or conflict fails
  /// closed and is retained. Caller must not race writers in another isolate.
  Future<void> repair(String key) => _locked(key, () async {
    final a = primary.get(key);
    final b = mirror.get(key);
    final current = _select(a, b);
    if (current == null) return;
    final encoded = current.encode();
    if (a != encoded) {
      await primary.put(key, encoded);
      await primary.flush();
    }
    if (b != encoded) {
      await mirror.put(key, encoded);
      await mirror.flush();
    }
  });
}

class _Replica {
  const _Replica(this.revision, this.deleted, this.value);
  final int revision;
  final bool deleted;
  final String? value;
  String encode() => jsonEncode({
    'version': 1,
    'revision': revision,
    'deleted': deleted,
    'value': value,
  });
}
