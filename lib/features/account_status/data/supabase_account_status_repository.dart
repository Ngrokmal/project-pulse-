import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/account_status.dart';

class SupabaseAccountStatusRepository implements AccountStatusRepository {
  SupabaseAccountStatusRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('account_status');

  final SupabaseClient _client;
  final AppLogger _log;

  @override
  Future<AccountStatusInfo> fetchMine(String userId) async {
    try {
      final data = await _client
          .from('account_status')
          .select('status, reason_text, ends_at')
          .eq('user_id', userId)
          .maybeSingle();
      // No row yet (e.g. migrations just applied) must not be treated as a ban.
      if (data == null) return AccountStatusInfo.activeInfo;
      return AccountStatusInfo.fromMap(data);
    } catch (e) {
      if (e is PostgrestException) {
        _log.warning('fetch_status_failed', error: e.code);
        // Fail open for a read error would be unsafe; fail closed but clearly
        // reported: the UI shows "could not verify account status" with retry.
        throw ServerFailure(safeCode: e.code ?? 'status_unavailable');
      }
      _log.error('fetch_status_failed', error: e);
      throw const ServerFailure(safeCode: 'status_unavailable');
    }
  }
}
