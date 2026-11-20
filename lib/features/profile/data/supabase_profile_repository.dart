import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/profile.dart';
import '../domain/profile_media.dart';
import '../domain/profile_privacy.dart';
import '../domain/profile_repository.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('profile');

  final SupabaseClient _client;
  final AppLogger _log;

  /// Every column 0012 added, named explicitly: `select *` would break the day
  /// somebody appends a column of a type this app cannot read.
  static const _columns =
      'id, display_name, username, bio, avatar_url, cover_url, joined_at, '
      'status_text, where_text, timezone, utc_offset_minutes, labels, '
      'last_seen_visible, read_receipts, photo_visible, push_notifications, '
      'chat_lock';

  /// The five 0001 columns, used only if the database has not run 0012 yet, so
  /// a half-migrated project shows a plain card instead of an error page.
  static const _columnsBase =
      'id, display_name, username, bio, avatar_url, cover_url, joined_at';

  @override
  Future<Profile> fetchMyProfile(String userId) async {
    try {
      final data = await _selectProfile(userId);
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

  Future<Map<String, dynamic>?> _selectProfile(String userId) async {
    try {
      return await _client
          .from('profiles')
          .select(_columns)
          .eq('id', userId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (!_looksLikeMissingColumn(e)) rethrow;
      _log.warning('profile_card_columns_missing', data: {'code': e.code});
      return await _client
          .from('profiles')
          .select(_columnsBase)
          .eq('id', userId)
          .maybeSingle();
    }
  }

  @override
  Future<Profile> updateMyProfile({
    required String userId,
    required String displayName,
    String? username,
    required String bio,
    String? statusText,
    String? whereText,
    String? timezone,
    int? utcOffsetMinutes,
    List<String>? labels,
  }) async {
    final normalized = (username == null || username.trim().isEmpty)
        ? null
        : Profile.normalizeUsername(username);

    final payload = <String, Object?>{
      'display_name': displayName.trim(),
      'username': normalized,
      'bio': bio.trim(),
      // Null-aware elements: a null simply omits the column, so a save that
      // only touched the name can never blank the status.
      'status_text': ?_orNull(statusText),
      'where_text': ?_orNull(whereText),
      'timezone': ?_orNull(timezone),
      'utc_offset_minutes': ?utcOffsetMinutes,
      'labels': ?_labelsOrNull(labels),
    };

    try {
      final data = await _client
          .from('profiles')
          .update(payload)
          .eq('id', userId)
          .select(_columns)
          .single();
      _log.info('profile_updated', correlationId: userId);
      return Profile.fromMap(data);
    } on PostgrestException catch (e) {
      if (!_looksLikeMissingColumn(e)) {
        throw _map(e, 'update_my_profile');
      }
      // 0012 has not been applied on this project: save what 0001 knows about
      // rather than losing the user's name and bio to an unsupported column.
      _log.warning('profile_card_columns_missing', data: {'code': e.code});
      return _updateBase(
        userId: userId,
        displayName: displayName,
        username: normalized,
        bio: bio,
      );
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'update_my_profile');
    }
  }

  Future<Profile> _updateBase({
    required String userId,
    required String displayName,
    required String? username,
    required String bio,
  }) async {
    try {
      final data = await _client
          .from('profiles')
          .update({
            'display_name': displayName.trim(),
            'username': username,
            'bio': bio.trim(),
          })
          .eq('id', userId)
          .select(_columnsBase)
          .single();
      return Profile.fromMap(data);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'update_my_profile');
    }
  }

  @override
  Future<ProfilePrivacy> updatePrivacy({
    required String userId,
    required PrivacyField field,
    required bool value,
  }) async {
    try {
      final data = await _client
          .from('profiles')
          .update(<String, Object?>{field.column: value})
          .eq('id', userId)
          .select(
            'last_seen_visible, read_receipts, photo_visible, '
            'push_notifications, chat_lock',
          )
          .single();
      _log.info('profile_privacy_updated', data: {'field': field.column});
      return ProfilePrivacy.fromMap(data);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'update_privacy');
    }
  }

  @override
  Future<List<ProfileMedia>> recentMedia({int limit = 9}) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return const <ProfileMedia>[];
    try {
      final rows = await _client
          .from('messages')
          .select('id, media_url, media_thumb_url, kind, created_at')
          .eq('sender_id', me)
          .not('media_url', 'is', null)
          .filter('deleted_at', 'is', null)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .where((row) => (row['media_url'] as String?)?.isNotEmpty ?? false)
          .map(ProfileMedia.fromMap)
          .toList(growable: false);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'recent_media');
    }
  }

  static String? _orNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String>? _labelsOrNull(List<String>? labels) =>
      labels == null ? null : _cleanLabels(labels);

  static List<String> _cleanLabels(List<String> labels) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in labels) {
      final label = raw.trim();
      if (label.isEmpty || label.length > Profile.labelMax) continue;
      if (!seen.add(label.toLowerCase())) continue;
      out.add(label);
      if (out.length == Profile.maxLabels) break;
    }
    return out;
  }

  /// Postgres `undefined_column` (42703) and PostgREST's `PGRST204` are both
  /// "that column is not in this schema yet".
  static bool _looksLikeMissingColumn(PostgrestException e) {
    final code = e.code ?? '';
    if (code == '42703' || code == 'PGRST204') return true;
    final message = e.message.toLowerCase();
    return message.contains('column') && message.contains('does not exist');
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
        // 23514 check_violation → a length or shape rule from 0001/0012
        '23514' => const ValidationFailure(
          'bio',
          'One of these lines is longer than the card allows.',
        ),
        // 42501 insufficient privilege → RLS said no
        '42501' => const ServerFailure(statusCode: 403, safeCode: 'not_allowed'),
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
        text.contains('host lookup') ||
        text.contains('timeout')) {
      final trimmed = e.toString();
      return NetworkFailure(
        timedOut: text.contains('timeout'),
        detail: trimmed.length > 160 ? trimmed.substring(0, 160) : trimmed,
      );
    }
    _log.error(op, error: e);
    return const ServerFailure();
  }
}
