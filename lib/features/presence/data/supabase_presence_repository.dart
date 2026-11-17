import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/presence_repository.dart';

/// Presence over PostgREST.
///
/// Heartbeats go through the `touch_presence()` RPC so the timestamp is the
/// **server's** clock, not the phone's. Reads are a single indexed row.
///
/// The watch is a 15 s poll rather than a Realtime channel on purpose: presence
/// is a *derived* value with a 90 s window, so a 15 s refresh is already finer
/// than the thing it measures, and it costs one tiny indexed SELECT instead of a
/// permanent socket per open chat.
class SupabasePresenceRepository implements PresenceRepository {
  SupabasePresenceRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('presence');

  final SupabaseClient _client;
  final AppLogger _log;

  static const Duration pollInterval = Duration(seconds: 15);

  @override
  Future<void> touch() async {
    try {
      await _client.rpc('touch_presence');
    } on PostgrestException catch (error) {
      // A failed heartbeat is not worth interrupting anyone over; the next one
      // is 30 s away.
      _log.warning('presence_touch_failed', data: {'code': error.code});
    } catch (error) {
      _log.warning('presence_touch_failed', data: {'error': '$error'});
    }
  }

  @override
  Future<DateTime?> lastSeenAt(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final row = await _client
          .from('user_presence')
          .select('last_seen_at')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return null;
      final raw = row['last_seen_at'] as String?;
      if (raw == null) return null;
      return DateTime.parse(raw).toLocal();
    } on PostgrestException catch (error) {
      throw ServerFailure(statusCode: int.tryParse(error.code ?? ''));
    } catch (_) {
      // Offline: presence is a nicety, not a reason to break a chat.
      return null;
    }
  }

  @override
  Stream<DateTime?> watch(String userId) async* {
    yield await lastSeenAt(userId);
    yield* Stream<void>.periodic(pollInterval)
        .asyncMap((_) => lastSeenAt(userId));
  }
}
