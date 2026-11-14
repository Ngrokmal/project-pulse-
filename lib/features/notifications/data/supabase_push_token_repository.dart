import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/push_token.dart';
import '../domain/push_token_repository.dart';

/// Talks to the `fcm_tokens` table, which is already RLS-verified against the
/// live project: own-row CRUD allowed, forged `user_id` rejected, tokens
/// shorter than 20 characters rejected by a CHECK constraint.
class SupabasePushTokenRepository implements PushTokenRepository {
  SupabasePushTokenRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('push');

  final SupabaseClient _client;
  final AppLogger _log;

  String get _uid {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        'Session expired. Please sign in again.',
        kind: AuthFailureKind.notConfigured,
      );
    }
    return user.id;
  }

  @override
  Future<void> register(PushToken token) async {
    final reason = PushToken.validate(token.value);
    if (reason != null) throw ValidationFailure('push_token', reason);

    final uid = _uid;
    try {
      await _client.from('fcm_tokens').insert({
        'user_id': uid,
        'token': token.value,
        'platform': token.platform,
        'is_active': true,
      });
    } on PostgrestException catch (e) {
      // 23505 = unique(token) already exists. It is either our own old row
      // (re-login on the same install) or a row owned by another account.
      if (e.code == '23505') {
        final mine = await _client
            .from('fcm_tokens')
            .select('id, user_id')
            .eq('token', token.value)
            .maybeSingle();
        if (mine != null && mine['user_id'] == uid) {
          await _client
              .from('fcm_tokens')
              .update({'is_active': true})
              .eq('token', token.value);
          _log.info('push_token_reactivated');
          return;
        }
        _log.warning('push_token_owned_by_other_account');
        throw const TokenOwnedByAnotherAccount();
      }
      _log.error('push_token_insert_failed', error: e.code ?? e.message);
      throw const ServerFailure(safeCode: 'push_sync_failed');
    }
  }

  @override
  Future<void> deactivate(PushToken token) async {
    try {
      await _client
          .from('fcm_tokens')
          .update({'is_active': false})
          .eq('token', token.value);
      _log.info('push_token_deactivated');
    } on PostgrestException catch (e) {
      // Best effort: sign-out must never be blocked by telemetry.
      _log.warning('push_token_deactivate_failed', data: {'code': e.code});
    }
  }

  @override
  Future<int> activeTokenCount() async {
    final rows = await _client
        .from('fcm_tokens')
        .select('id')
        .eq('is_active', true);
    return rows.length;
  }
}
