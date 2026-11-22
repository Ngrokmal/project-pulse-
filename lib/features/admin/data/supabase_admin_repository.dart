import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../domain/admin_repository.dart';

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);
  final SupabaseClient _client;

  Future<T> _safe<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      throw ServerFailure(safeCode: e.code ?? 'admin_unavailable');
    } catch (_) {
      throw const ServerFailure(safeCode: 'admin_unavailable');
    }
  }

  @override
  Future<bool> isAdmin() => _safe(() async {
    final result = await _client.rpc('pulse_is_admin');
    return result == true;
  });

  @override
  Future<List<ManagedUser>> users({String query = '', int offset = 0}) =>
      _safe(() async {
        final result = await _client.rpc(
          'pulse_admin_list_users',
          params: {'p_query': query.trim(), 'p_limit': 25, 'p_offset': offset},
        );
        return (result as List)
            .map(
              (row) =>
                  ManagedUser.fromMap(Map<String, dynamic>.from(row as Map)),
            )
            .toList();
      });

  @override
  Future<void> setControl(String userId, String control, bool enabled) => _safe(
    () async {
      await _client.rpc(
        'pulse_admin_set_user_control',
        params: {'p_user': userId, 'p_control': control, 'p_enabled': enabled},
      );
    },
  );

  @override
  Future<void> setSuspension(
    String userId,
    bool suspended, {
    DateTime? until,
  }) => _safe(() async {
    await _client.rpc(
      'pulse_admin_set_suspension',
      params: {
        'p_user': userId,
        'p_suspend': suspended,
        'p_ends_at': until?.toUtc().toIso8601String(),
        'p_reason': null,
      },
    );
  });

  @override
  Future<void> setErrorMessage(String code, String message) => _safe(() async {
    await _client.rpc(
      'pulse_admin_set_error_message',
      params: {'p_code': code, 'p_message': message},
    );
  });
}
