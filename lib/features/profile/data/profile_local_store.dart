import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../../core/logging/app_logger.dart';
import '../domain/pending_write.dart';
import '../domain/profile.dart';

/// Offline-first storage for the profile card (Hive).
///
/// Two jobs, the same two the chat store has:
///   • cache  — the last profile row, so opening Profile on a dead connection
///              shows the real card instead of an error page.
///   • outbox — settings switches the server has not accepted yet, so a toggle
///              flipped in a lift is applied later instead of bouncing back.
///
/// Nothing here is authoritative: the server row always wins once it answers.
class ProfileLocalStore {
  ProfileLocalStore._(this._cache, this._outbox);

  static const _cacheBox = 'profile_cache';
  static const _outboxBox = 'profile_outbox';

  static final _log = AppLogger('profile.store');

  final Box<String> _cache;
  final Box<String> _outbox;

  static ProfileLocalStore? _instance;
  static ProfileLocalStore? get instance => _instance;

  /// Called once at boot. A failure is reported, never fatal: without Hive the
  /// card still works online, it just loses the cache.
  static Future<void> open() async {
    if (_instance != null) return;
    try {
      await Hive.initFlutter();
      final cache = await Hive.openBox<String>(_cacheBox);
      final outbox = await Hive.openBox<String>(_outboxBox);
      _instance = ProfileLocalStore._(cache, outbox);
      _log.info(
        'profile_store_ready',
        data: {'cached': cache.length, 'queued': outbox.length},
      );
    } catch (e) {
      _log.error('profile_store_open_failed', error: e);
    }
  }

  // ─────────────────────────────────────────────────────────────── cache

  void cacheProfile(Profile profile) {
    try {
      _cache.put(profile.id, jsonEncode(profile.toMap()));
    } catch (e) {
      _log.warning('profile_cache_write_failed', data: {'error': '$e'});
    }
  }

  Profile? cachedProfile(String userId) {
    final raw = _cache.get(userId);
    if (raw == null) return null;
    try {
      return Profile.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      _log.warning('profile_cache_read_failed', data: {'error': '$e'});
      return null;
    }
  }

  void forgetProfile(String userId) => _cache.delete(userId);

  // ────────────────────────────────────────────────────────────── outbox

  List<PendingWrite> pending(String userId) {
    final writes = <PendingWrite>[];
    for (final raw in _outbox.values) {
      try {
        final write = PendingWrite.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (write.userId == userId) writes.add(write);
      } catch (_) {
        // A corrupt entry must not wedge the queue forever.
      }
    }
    writes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return writes;
  }

  /// Adds a write, folding it into an older one that touches the same columns
  /// so flipping a switch five times offline drains as one request.
  void enqueue(PendingWrite write) {
    for (final existing in pending(write.userId)) {
      final sameTarget =
          existing.values.keys.toSet().containsAll(write.values.keys) &&
          write.values.keys.every((key) => existing.values.containsKey(key));
      if (!sameTarget) continue;
      final merged = PendingWrite(
        id: existing.id,
        userId: write.userId,
        values: <String, Object?>{...existing.values, ...write.values},
        createdAt: existing.createdAt,
      );
      _outbox.put(existing.id, jsonEncode(merged.toJson()));
      return;
    }
    _outbox.put(write.id, jsonEncode(write.toJson()));
  }

  void resolve(String writeId) => _outbox.delete(writeId);

  void clearOutbox(String userId) {
    for (final write in pending(userId)) {
      _outbox.delete(write.id);
    }
  }

  /// Calls [attempt] for each queued write, oldest first, stopping at the first
  /// failure so ordering is preserved. Returns how many reached the server.
  Future<int> drain(
    String userId,
    Future<void> Function(PendingWrite write) attempt,
  ) async {
    var delivered = 0;
    for (final write in pending(userId)) {
      try {
        await attempt(write);
        _outbox.delete(write.id);
        delivered++;
      } catch (e) {
        _log.warning('profile_outbox_drain_failed', data: {'error': '$e'});
        break;
      }
    }
    return delivered;
  }
}
