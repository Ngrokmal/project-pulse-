import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/profile.dart';
import '../domain/profile_repository.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('profile');

  final SupabaseClient _client;
  final AppLogger _log;

  static const _columns =
      'id, display_name, username, bio, avatar_url, cover_url, joined_at';

  @override
  Future<Profile> fetchMyProfile(String userId) async {
    try {
      final data = await _client
          .from('profiles')
          .select(_columns)
          .eq('id', userId)
          .maybeSingle();
      if (data == null) {
        // The signup trigger creates the row; a missing row is a real fault.
        throw const ServerFailure(safeCode: 'profile_missing');
      }
      return Profile.fromMap(data);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'fetch_my_profile');
    }
  }

  @override
  Future<Profile> updateMyProfile({
    required String userId,
    required String displayName,
    String? username,
    required String bio,
  }) async {
    final normalized = (username == null || username.trim().isEmpty)
        ? null
        : Profile.normalizeUsername(username);
    try {
      final data = await _client
          .from('profiles')
          .update({
            'display_name': displayName.trim(),
            'username': normalized,
            'bio': bio.trim(),
          })
          .eq('id', userId)
          .select(_columns)
          .single();
      _log.info('profile_updated', correlationId: userId);
      return Profile.fromMap(data);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'update_my_profile');
    }
  }

  AppFailure _map(Object e, String op) {
    if (e is PostgrestException) {
      _log.warning(op, error: '${e.code}');
      return switch (e.code) {
        // 23505 unique_violation → username already taken
        '23505' => const ValidationFailure(
          'username',
          'That username is already taken.',
        ),
        // 42501 insufficient privilege → RLS said no
        '42501' => const ServerFailure(
          statusCode: 403,
          safeCode: 'not_allowed',
        ),
        // PGRST205 table not found → migrations not applied yet
        'PGRST205' => const ServerFailure(safeCode: 'schema_missing'),
        _ => ServerFailure(safeCode: e.code ?? 'postgrest_error'),
      };
    }
    if (e is AuthException) {
      return const AuthFailure('Your session expired. Please log in again.');
    }
    final text = e.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('connection') ||
        text.contains('timeout')) {
      return const NetworkFailure();
    }
    _log.error(op, error: e);
    return const ServerFailure();
  }
}
