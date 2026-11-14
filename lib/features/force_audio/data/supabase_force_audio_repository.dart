import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/force_audio_alert.dart';
import '../domain/force_audio_repository.dart';

class SupabaseForceAudioRepository implements ForceAudioRepository {
  SupabaseForceAudioRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('force_audio.api');

  static const _columns =
      'id, request_id, conversation_id, message_id, sender_id, recipient_id, '
      'media_url, duration_ms, size_bytes, mime_type, state, created_at, '
      'expires_at, played_at';

  final SupabaseClient _client;
  final AppLogger _log;

  String get _me {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        'Session expired. Please sign in again.',
        kind: AuthFailureKind.notConfigured,
      );
    }
    return user.id;
  }

  /// Creates the alert through the `force-audio-create` Edge Function, which
  /// inserts it under the caller's JWT **and** pushes the recipient. If the
  /// function is not deployed (404) the call falls back to a direct insert: the
  /// alert still exists and RLS still enforces every rule, only the push is lost.
  @override
  Future<ForceAudioAlert> createAlert({
    required String requestId,
    required String conversationId,
    required String recipientId,
    required String mediaUrl,
    required int durationMs,
    required int sizeBytes,
    String? messageId,
    String mimeType = 'audio/mp4',
  }) async {
    final me = _me;
    final payload = {
      'requestId': requestId,
      'conversationId': conversationId,
      'recipientId': recipientId,
      'mediaUrl': mediaUrl,
      'durationMs': durationMs,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
      'messageId': ?messageId,
    };

    try {
      final response = await _client.functions.invoke(
        'force-audio-create',
        body: payload,
      );
      final data = response.data;
      if (data is Map && data['alert'] is Map) {
        final alert = ForceAudioAlert.fromMap(
          Map<String, dynamic>.from(data['alert'] as Map),
        );
        final push = data['push'];
        _log.info(
          'alert_created',
          data: {
            'id': alert.id,
            'push': push is Map ? '${push['sent']}/${push['failed']}' : 'n/a',
          },
        );
        return alert;
      }
      throw const ServerFailure(safeCode: 'alert_create');
    } on FunctionException catch (e) {
      // 404 / not deployed: keep working, just without a push.
      if (e.status == 404) {
        _log.info('alert_function_missing');
        return _insertDirect(
          me: me,
          requestId: requestId,
          conversationId: conversationId,
          recipientId: recipientId,
          mediaUrl: mediaUrl,
          durationMs: durationMs,
          sizeBytes: sizeBytes,
          messageId: messageId,
          mimeType: mimeType,
        );
      }
      if (e.status == 400) {
        throw const ValidationFailure(
          'force_audio',
          'That recording was rejected: it must be 0.5-70 s and at most 10 MB.',
        );
      }
      if (e.status == 403) {
        throw const ValidationFailure(
          'force_audio',
          'You cannot send a Force Audio here.',
        );
      }
      _log.error('alert_function_failed', data: {'status': e.status});
      throw const ServerFailure(safeCode: 'alert_create');
    } on SocketException {
      throw const NetworkFailure();
    }
  }

  Future<ForceAudioAlert> _insertDirect({
    required String me,
    required String requestId,
    required String conversationId,
    required String recipientId,
    required String mediaUrl,
    required int durationMs,
    required int sizeBytes,
    String? messageId,
    required String mimeType,
  }) async {
    try {
      final row = await _client
          .from('force_audio_alerts')
          .insert({
            'request_id': requestId,
            'conversation_id': conversationId,
            'message_id': ?messageId,
            'sender_id': me,
            'recipient_id': recipientId,
            'media_url': mediaUrl,
            'duration_ms': durationMs,
            'size_bytes': sizeBytes,
            'mime_type': mimeType,
          })
          .select(_columns)
          .single();
      return ForceAudioAlert.fromMap(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final existing = await _client
            .from('force_audio_alerts')
            .select(_columns)
            .eq('request_id', requestId)
            .maybeSingle();
        if (existing != null) return ForceAudioAlert.fromMap(existing);
      }
      _log.error('alert_insert_failed', data: {'code': e.code});
      throw ServerFailure(statusCode: null, safeCode: e.code ?? 'alert_create');
    } on SocketException {
      throw const NetworkFailure();
    }
  }

  @override
  Future<ForceAudioAlert?> fetch(String alertId) async {
    try {
      final row = await _client
          .from('force_audio_alerts')
          .select(_columns)
          .eq('id', alertId)
          .maybeSingle();
      return row == null ? null : ForceAudioAlert.fromMap(row);
    } on PostgrestException {
      throw const ServerFailure(safeCode: 'alert_fetch');
    } on SocketException {
      throw const NetworkFailure();
    }
  }

  @override
  Future<ForceAudioAlert?> fetchByMessage(String messageId) async {
    try {
      final row = await _client
          .from('force_audio_alerts')
          .select(_columns)
          .eq('message_id', messageId)
          .maybeSingle();
      return row == null ? null : ForceAudioAlert.fromMap(row);
    } on PostgrestException {
      return null;
    } on SocketException {
      throw const NetworkFailure();
    }
  }

  @override
  Future<void> markDelivered(String alertId) async {
    try {
      await _client
          .from('force_audio_alerts')
          .update({'state': 'delivered'})
          .eq('id', alertId)
          .eq('state', 'created');
    } on PostgrestException {
      // Only the receiver may do this, and only once; losing the race is fine.
    }
  }

  @override
  Future<void> markPlayed(String alertId) async {
    try {
      await _client
          .from('force_audio_alerts')
          .update({'state': 'played'})
          .eq('id', alertId)
          .neq('state', 'played');
    } on PostgrestException catch (e) {
      // Terminal state, expiry race, or already played elsewhere: all benign.
      _log.info('mark_played_skipped', data: {'code': e.code});
    }
  }

  /// Realtime feed for the receiver: a new alert arrives while the chat is open.
  Stream<ForceAudioAlert> watch(String conversationId) {
    return _client
        .from('force_audio_alerts')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .map((rows) => rows.map(ForceAudioAlert.fromMap).toList())
        .expand((alerts) => alerts);
  }
}
