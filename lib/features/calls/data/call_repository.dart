import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/call_session.dart';

/// Everything the call feature needs from the server. Pure data, no UI.
abstract class CallRepository {
  /// The signed-in user, or null when there is no session.
  String? get currentUserId;

  Future<String> start(String conversationId, CallKind kind);
  Future<Map<String, dynamic>?> byId(String callId);
  Future<Map<String, dynamic>?> myIncoming();

  /// Display name for a user id; never throws for a missing profile.
  Future<String> peerName(String userId);
  Future<void> accept(String callId);
  Future<void> confirmConnected(String callId);
  Future<void> decline(String callId);
  Future<void> end(String callId, {String reason});
  Future<void> setReconnecting(String callId, {required bool on});
  Stream<Map<String, dynamic>> watch(String callId);
}

class SupabaseCallRepository implements CallRepository {
  SupabaseCallRepository(this._client, this._me);

  final SupabaseClient _client;
  final String? Function() _me;
  final _log = AppLogger('calls');

  @override
  String? get currentUserId => _me();

  String get _myId {
    final id = _me();
    if (id == null) {
      throw const AuthFailure(
        'Session expired. Please sign in again.',
        kind: AuthFailureKind.notConfigured,
      );
    }
    return id;
  }

  @override
  Future<String> start(String conversationId, CallKind kind) async {
    try {
      final id = await _client.rpc(
        'start_call',
        params: {'p_conversation': conversationId, 'p_kind': kind.name},
      );
      return id as String;
    } on PostgrestException catch (e) {
      throw _map(e, 'start');
    }
  }

  @override
  Future<Map<String, dynamic>?> byId(String callId) async {
    try {
      final rows = await _client
          .from('calls')
          .select()
          .eq('id', callId)
          .limit(1);
      return rows.isEmpty ? null : rows.first;
    } on PostgrestException catch (e) {
      throw _map(e, 'byId');
    }
  }

  @override
  Future<Map<String, dynamic>?> myIncoming() async {
    try {
      final rows = await _client
          .from('calls')
          .select()
          .eq('callee_id', _myId)
          .eq('state', 'ringing')
          .order('created_at', ascending: false)
          .limit(1);
      return rows.isEmpty ? null : rows.first;
    } on PostgrestException catch (e) {
      throw _map(e, 'incoming');
    }
  }

  @override
  Future<String> peerName(String userId) async {
    try {
      final rows = await _client
          .from('profiles')
          .select('display_name, username')
          .eq('id', userId)
          .limit(1);
      if (rows.isEmpty) return 'Pulse user';
      final name = (rows.first['display_name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) return name;
      final handle = rows.first['username'] as String?;
      return handle == null ? 'Pulse user' : '@$handle';
    } on PostgrestException {
      return 'Pulse user';
    }
  }

  @override
  Future<void> accept(String callId) =>
      _rpc('accept_call', 'accept', {'p_call': callId});

  @override
  Future<void> confirmConnected(String callId) =>
      _rpc('confirm_call_connected', 'confirmConnected', {'p_call': callId});

  @override
  Future<void> decline(String callId) =>
      _rpc('decline_call', 'decline', {'p_call': callId});

  @override
  Future<void> end(String callId, {String reason = 'hangup'}) =>
      _rpc('end_call', 'end', {'p_call': callId, 'p_reason': reason});

  @override
  Future<void> setReconnecting(String callId, {required bool on}) => _rpc(
    'set_call_reconnecting',
    'setReconnecting',
    {'p_call': callId, 'p_on': on},
  );

  @override
  Stream<Map<String, dynamic>> watch(String callId) {
    return _client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callId)
        .map((rows) => rows.isEmpty ? <String, dynamic>{} : rows.first)
        .where((row) => row.isNotEmpty);
  }

  Future<void> _rpc(String fn, String op, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw _map(e, op);
    }
  }

  AppFailure _map(PostgrestException e, String op) {
    _log.warning('call_$op', error: '${e.code}');
    final text = e.message.toLowerCase();
    if (e.code == 'PCTRL' && e.message == 'call_start_disabled') {
      return const AdminControlFailure('call_start_disabled');
    }
    for (final reason in const [
      'already_in_call',
      'peer_busy',
      'group_calls_not_supported',
      'no_peer',
      'not_a_member',
      'not_allowed',
      'invalid_kind',
      'invalid_transition',
    ]) {
      if (text.contains(reason)) {
        return ServerFailure(safeCode: reason, statusCode: 409);
      }
    }
    if (text.contains('socket') || text.contains('connection')) {
      return NetworkFailure(detail: '${e.code}: ${e.message}');
    }
    return ServerFailure(safeCode: e.code ?? 'call_error');
  }
}

final callRepositoryProvider = Provider<CallRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure('Supabase is not configured.');
  }
  final auth = ref.watch(authControllerProvider);
  return SupabaseCallRepository(
    Supabase.instance.client,
    () => auth is AuthSignedIn ? auth.user.id : null,
  );
});
