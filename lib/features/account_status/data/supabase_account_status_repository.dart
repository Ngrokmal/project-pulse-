import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/account_status.dart';

class SupabaseAccountStatusRepository implements AccountStatusRepository {
  SupabaseAccountStatusRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('account_status');

  final SupabaseClient _client;
  final AppLogger _log;

  static const _columns = 'status, reason_text, ends_at, case_code, starts_at';

  @override
  Future<AccountStatusInfo> fetchMine(String userId) async {
    try {
      final data = await _client
          .from('account_status')
          .select(_columns)
          .eq('user_id', userId)
          .maybeSingle();
      // No row yet (e.g. migrations just applied) must not be treated as a ban.
      if (data == null) return AccountStatusInfo.activeInfo;
      return AccountStatusInfo.fromMap(data);
    } catch (e) {
      if (e is PostgrestException) {
        _log.warning('fetch_status_failed', error: e.code);
        // Fail open on a read error would be unsafe; fail closed but clearly
        // reported: the UI shows "could not verify account status" with retry.
        throw ServerFailure(safeCode: e.code ?? 'status_unavailable');
      }
      _log.error('fetch_status_failed', error: e);
      throw const ServerFailure(safeCode: 'status_unavailable');
    }
  }

  /// One row, filtered by the user id the server already scoped: Realtime
  /// applies the same row-level policy as a `select`, so this stream can only
  /// ever carry the caller's own status.
  @override
  Stream<AccountStatusInfo> watch(String userId) {
    final controller = StreamController<AccountStatusInfo>();
    RealtimeChannel? channel;

    Future<void> push() async {
      try {
        final info = await fetchMine(userId);
        if (!controller.isClosed) controller.add(info);
      } catch (e) {
        _log.warning('watch_refetch_failed', error: e);
      }
    }

    controller.onListen = () {
      channel = _client.channel('account-status:$userId');
      channel!
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'account_status',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              final row = payload.newRecord;
              if (row.isEmpty) {
                // A delete (an account being removed) is not a suspension;
                // re-read instead of guessing.
                unawaited(push());
                return;
              }
              if (!controller.isClosed) {
                controller.add(AccountStatusInfo.fromMap(row));
              }
            },
          )
          .subscribe();
    };

    controller.onCancel = () async {
      final current = channel;
      channel = null;
      if (current != null) {
        await _client.removeChannel(current);
      }
    };

    return controller.stream;
  }

  @override
  Future<AccountAppeal> submitAppeal({
    required String userId,
    required String caseCode,
    required String note,
  }) async {
    try {
      final row = await _client
          .from('account_appeals')
          .insert({
            'user_id': userId,
            'case_code': caseCode,
            'note': note.trim(),
          })
          .select()
          .single();
      return AccountAppeal.fromMap(row);
    } on PostgrestException catch (e) {
      _log.warning('appeal_failed', error: e.code);
      // 23505 = an appeal is already open for this account. That is not a
      // failure to the person reading the screen: it is the truth.
      if (e.code == '23505') throw const AppealAlreadyOpenFailure();
      if (e.code == '42501' || e.code == 'PULSE') {
        throw AccountSuspendedFailure(detail: e.message);
      }
      throw ServerFailure(safeCode: e.code ?? 'appeal_failed');
    }
  }

  @override
  Future<AccountAppeal?> fetchLatestAppeal(String userId) async {
    try {
      final row = await _client
          .from('account_appeals')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : AccountAppeal.fromMap(row);
    } catch (e) {
      // Reading the appeal is a nicety; never fail the screen over it.
      _log.warning('appeal_read_failed', error: e);
      return null;
    }
  }
}
