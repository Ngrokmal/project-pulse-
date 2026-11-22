import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/account_session.dart';
import '../domain/blocked_person.dart';
import '../domain/profile.dart';
import '../domain/profile_media.dart';
import '../domain/profile_photo.dart';
import '../domain/profile_privacy.dart';
import '../domain/profile_repository.dart';
import '../domain/profile_visitor.dart';
import '../domain/safety_action.dart';

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

  @override
  Future<Profile> fetchProfile(String userId) async {
    try {
      final data = await _selectProfile(userId);
      if (data == null) {
        throw const ServerFailure(safeCode: 'profile_missing');
      }
      final profile = Profile.fromMap(data);
      // The card is rendered as a visitor sees it: a photo switched off is not
      // delivered, even though the row still carries the URL.
      return profile.privacy.photoVisible
          ? profile
          : Profile.fromMap(<String, dynamic>{...data, 'avatar_url': null});
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'fetch_profile');
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

  // ────────────────────────────────────────────────────────── partial write

  @override
  Future<void> patchProfile({
    required String userId,
    required Map<String, Object?> values,
  }) async {
    if (values.isEmpty) return;
    try {
      await _client.from('profiles').update(values).eq('id', userId);
      _log.info('profile_patched', data: {'columns': values.keys.join(',')});
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'patch_profile');
    }
  }

  // ──────────────────────────────────────────────────────────────── photo

  static const String _avatarBucket = 'avatars';

  @override
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String mimeType,
    required DateTime takenAt,
  }) async {
    final path = ProfilePhoto.objectPath(
      userId: userId,
      mimeType: mimeType,
      at: takenAt,
    );
    try {
      await _client.storage
          .from(_avatarBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      final url = _client.storage.from(_avatarBucket).getPublicUrl(path);
      await _client
          .from('profiles')
          .update(<String, Object?>{'avatar_url': url})
          .eq('id', userId);
      _log.info('avatar_uploaded', data: {'bytes': bytes.length});
      return url;
    } on StorageException catch (e) {
      _log.warning('avatar_upload_failed', data: {'status': '${e.statusCode}'});
      // StorageException carries a *string* status ("413"), unlike PostgREST's
      // int; parse it so the retry policy (>=500 retries) still works.
      final status = int.tryParse('${e.statusCode}');
      if (status == 403) {
        // A Storage RLS denial does not carry our trigger's SQLSTATE. Ask the
        // server about this account's photo policy; if unavailable (including
        // older servers), keep the generic Storage error instead of guessing.
        bool? photoAllowed;
        try {
          final value = await _client
              .rpc('pulse_own_photo_change_allowed')
              .timeout(const Duration(seconds: 2));
          if (value is bool) photoAllowed = value;
        } catch (_) {
          // The existing safe Storage fallback is retained.
        }
        if (photoAllowed == false) {
          throw const AdminControlFailure('profile_photo_change_disabled');
        }
      }
      throw ServerFailure(statusCode: status, safeCode: 'avatar_upload_failed');
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'upload_avatar');
    }
  }

  @override
  Future<void> removeAvatar({
    required String userId,
    String? existingUrl,
  }) async {
    try {
      await _client
          .from('profiles')
          .update(<String, Object?>{'avatar_url': null})
          .eq('id', userId);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'remove_avatar');
    }
    final path = _objectPathFromUrl(existingUrl);
    if (path == null) return;
    try {
      await _client.storage.from(_avatarBucket).remove(<String>[path]);
    } catch (e) {
      // The column is already clear; a stranded object is untidy, not a bug the
      // person should ever see.
      _log.warning('avatar_object_orphaned', error: e);
    }
  }

  /// `…/object/public/avatars/<uid>/avatar-1.jpg` → `<uid>/avatar-1.jpg`.
  static String? _objectPathFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final marker = '/object/public/$_avatarBucket/';
    final at = url.indexOf(marker);
    if (at < 0) return null;
    final path = url.substring(at + marker.length);
    return path.isEmpty ? null : Uri.decodeComponent(path);
  }

  // ────────────────────────────────────────────────────────────── account

  @override
  Future<List<AccountSession>> sessions() async {
    if (_client.auth.currentUser == null) return const <AccountSession>[];
    try {
      final rows = await _client
          .from('account_device_history')
          .select('device_id, first_seen, last_seen, devices(platform)')
          .order('last_seen', ascending: false)
          .limit(20);
      return rows
          .map((row) {
            final device = row['devices'];
            return AccountSession.fromMap(<String, dynamic>{
              'device_id': row['device_id'],
              'first_seen': row['first_seen'],
              'last_seen': row['last_seen'],
              'platform': device is Map ? device['platform'] : 'android',
            });
          })
          .toList(growable: false);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'sessions');
    }
  }

  @override
  Future<void> signOutOtherSessions() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.others);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'sign_out_others');
    }
  }

  // ─────────────────────────────────────────────────────────────── safety

  String get _me {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure('Your session expired. Please log in again.');
    }
    return id;
  }

  @override
  Future<void> blockUser(String targetUserId) async {
    final me = _me;
    if (me == targetUserId) return;
    try {
      await _client
          .from('blocks')
          .upsert(
            <String, Object?>{'blocker': me, 'blocked': targetUserId},
            onConflict: 'blocker,blocked',
            ignoreDuplicates: true,
          );
      _log.info('user_blocked');
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'block_user');
    }
  }

  @override
  Future<void> unblockUser(String targetUserId) async {
    final me = _me;
    try {
      await _client
          .from('blocks')
          .delete()
          .eq('blocker', me)
          .eq('blocked', targetUserId);
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'unblock_user');
    }
  }

  @override
  @override
  Future<List<BlockedPerson>> blockedPeople() async {
    if (_client.auth.currentUser == null) return const <BlockedPerson>[];
    try {
      final rows = await _client.rpc<dynamic>('blocked_people');
      final list = rows is List ? rows : const <dynamic>[];
      return [
        for (final row in list)
          if (row is Map) BlockedPerson.fromMap(Map<String, dynamic>.from(row)),
      ];
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'blocked_people');
    }
  }

  @override
  Future<void> recordProfileVisit(String targetUserId) async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc<dynamic>(
        'record_profile_visit',
        params: <String, dynamic>{'target': targetUserId},
      );
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'record_profile_visit');
    }
  }

  @override
  Future<List<ProfileVisitor>> profileVisitors({int limit = 50}) async {
    if (_client.auth.currentUser == null) return const <ProfileVisitor>[];
    try {
      final rows = await _client.rpc<dynamic>(
        'profile_visitors',
        params: <String, dynamic>{'limit_count': limit},
      );
      final list = rows is List ? rows : const <dynamic>[];
      return [
        for (final row in list)
          if (row is Map)
            ProfileVisitor.fromMap(Map<String, dynamic>.from(row)),
      ];
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'profile_visitors');
    }
  }

  @override
  Future<bool> hasBlocked(String targetUserId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return false;
    try {
      final rows = await _client
          .from('blocks')
          .select('blocked')
          .eq('blocker', me)
          .eq('blocked', targetUserId)
          .limit(1);
      return rows.isNotEmpty;
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'has_blocked');
    }
  }

  @override
  Future<void> reportUser({
    required String targetUserId,
    required ReportReason reason,
  }) async {
    final me = _me;
    if (me == targetUserId) return;
    try {
      await _client.from('reports').insert(<String, Object?>{
        'reporter': me,
        'reported': targetUserId,
        'reason': reason.value,
      });
      _log.info('user_reported', data: {'reason': reason.name});
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'report_user');
    }
  }

  @override
  Future<void> clearChatWith(String otherUserId) async {
    final me = _me;
    // Same canonical key the SQL uses: least(uuid) : greatest(uuid).
    final pairKey = me.compareTo(otherUserId) < 0
        ? '$me:$otherUserId'
        : '$otherUserId:$me';
    try {
      final row = await _client
          .from('conversations')
          .select('id')
          .eq('pair_key', pairKey)
          .maybeSingle();
      final id = row?['id'] as String?;
      if (id == null) return; // nothing was ever said: nothing to clear
      await _client.rpc(
        'clear_conversation',
        params: <String, Object?>{'conv': id},
      );
      _log.info('chat_cleared');
    } on AppFailure {
      rethrow;
    } catch (e) {
      throw _map(e, 'clear_chat');
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
        'PCTRL' when e.message == 'profile_photo_change_disabled' =>
          const AdminControlFailure('profile_photo_change_disabled'),
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
