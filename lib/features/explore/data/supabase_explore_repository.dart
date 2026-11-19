import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/explore_repository.dart';
import '../domain/friend_request.dart';
import '../domain/friend_state.dart';
import '../domain/people_match.dart';
import '../domain/people_search.dart';
import '../domain/person.dart';
import 'explore_row_mapper.dart';

/// Explore over PostgREST.
///
/// Reads and writes all go through the RPCs in `0010_friends.sql` — the rules
/// (who may accept what, what counts as a match) live in the database, not in a
/// client that could be replayed. Nothing here is called per keystroke: the
/// search sheet submits once, on purpose.
///
/// If the migration has not been applied yet, the repository degrades instead of
/// throwing at the first frame:
///  • search falls back to a `profiles` scan ranked by the *same* [PeopleMatch]
///    rule the SQL uses;
///  • the three lists come back empty (there is nothing to lose — no tables);
///  • a write says so plainly with [FeatureUnavailableFailure].
class SupabaseExploreRepository implements ExploreRepository {
  SupabaseExploreRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('explore');

  final SupabaseClient _client;
  final AppLogger _log;

  static const Duration _timeout = Duration(seconds: 12);

  /// Postgres/PostgREST codes that mean "this backend has not run 0010 yet".
  static const Set<String> _missingBackendCodes = {
    '42883', // undefined_function
    '42P01', // undefined_table
    'PGRST202', // no function matched in schema cache
    'PGRST205', // table not found in schema cache
  };

  /// Thrown by the functions themselves; surfaced as safe codes so the UI can
  /// keep a friendly sentence per case.
  static const Set<String> knownActionCodes = {
    'request_not_open',
    'not_your_request',
    'invalid_target',
    'request_already_open',
    'not_authenticated',
    'nothing_to_undo',
  };

  // ------------------------------------------------------------------ reads
  @override
  Future<List<FriendRequest>> incomingRequests() =>
      _requestList('explore_incoming');

  @override
  Future<List<FriendRequest>> sentRequests() => _requestList('explore_sent');

  Future<List<FriendRequest>> _requestList(String rpc) async {
    try {
      final rows = await _rows(rpc);
      return rows.map(ExploreRowMapper.request).toList(growable: false);
    } on FeatureUnavailableFailure {
      return const <FriendRequest>[];
    }
  }

  @override
  Future<List<Person>> friends() async {
    try {
      final rows = await _rows('explore_friends');
      return rows.map(ExploreRowMapper.person).toList(growable: false);
    } on FeatureUnavailableFailure {
      return const <Person>[];
    }
  }

  @override
  Future<int> friendsCount() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return 0;
    try {
      final response = await _client
          .from('friendships')
          .select('friend_id')
          .eq('user_id', me)
          .count(CountOption.exact)
          .timeout(_timeout);
      return response.count;
    } on PostgrestException catch (error) {
      if (_missingBackendCodes.contains(error.code)) return 0;
      throw _map(error, 'friends_count');
    } on Object catch (error) {
      throw _mapGeneric(error, 'friends_count');
    }
  }

  @override
  Future<int> networkSize() async {
    try {
      final response = await _client
          .from('profiles')
          .select('id')
          .count(CountOption.exact)
          .timeout(_timeout);
      return response.count;
    } on Object {
      // The population line is decoration with a number in it; never break the
      // sheet over it.
      return 0;
    }
  }

  @override
  Future<PeopleSearch> searchPeople(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return PeopleSearch.none;

    final size = await networkSize();

    try {
      final rows = await _rows(
        'search_people',
        params: {'q': trimmed, 'max_rows': limit},
      );
      return PeopleSearch(
        query: trimmed,
        hits: rows.map(ExploreRowMapper.hit).toList(growable: false),
        networkSize: size,
      );
    } on FeatureUnavailableFailure {
      return _localSearch(trimmed, limit, size);
    }
  }

  /// Fallback used only when `search_people` does not exist yet: one bounded
  /// `profiles` read, ranked by the identical rule, with every state `none`
  /// because there are no request tables to consult.
  Future<PeopleSearch> _localSearch(String query, int limit, int size) async {
    final me = _client.auth.currentUser?.id;
    try {
      final rows = await _client
          .from('profiles')
          .select('id, display_name, username, avatar_url')
          .neq('id', me ?? '')
          .limit(300)
          .timeout(_timeout);

      final hits = <SearchHit>[];
      for (final row in rows) {
        final person = ExploreRowMapper.person(<String, dynamic>{
          ...row,
          'person_id': row['id'],
        });
        final score = PeopleMatch.score(
          query: query,
          displayName: person.displayName,
          handle: person.handle,
        );
        if (!PeopleMatch.passes(score)) continue;
        hits.add(
          SearchHit(person: person, state: FriendState.none, score: score),
        );
      }
      hits.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return b.person.mutualCount.compareTo(a.person.mutualCount);
      });
      return PeopleSearch(
        query: query,
        hits: hits.take(limit).toList(growable: false),
        networkSize: size,
      );
    } on PostgrestException catch (error) {
      throw _map(error, 'search_people_local');
    } on Object catch (error) {
      throw _mapGeneric(error, 'search_people_local');
    }
  }

  @override
  Future<List<SearchHit>> nearMisses(String query, {int limit = 2}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <SearchHit>[];
    try {
      final rows = await _rows(
        'near_people',
        params: {'q': trimmed, 'max_rows': limit},
      );
      return rows.map(ExploreRowMapper.hit).toList(growable: false);
    } on FeatureUnavailableFailure {
      return const <SearchHit>[];
    }
  }

  // ----------------------------------------------------------------- writes
  @override
  Future<FriendState> sendRequest(String personId) async {
    final data = await _rpcOne('send_friend_request', {'p_target': personId});
    return FriendState.parse(data['state'] as String?);
  }

  @override
  Future<void> acceptRequest(String requestId) =>
      _rpcOne('accept_friend_request', {'p_request': requestId});

  @override
  Future<void> declineRequest(String requestId) =>
      _rpcOne('decline_friend_request', {'p_request': requestId});

  @override
  Future<void> cancelRequest(String requestId) =>
      _rpcOne('cancel_friend_request', {'p_request': requestId});

  @override
  Future<void> undoDecline(String requestId) =>
      _rpcOne('undo_decline_friend_request', {'p_request': requestId});

  @override
  Future<void> cancelRequestTo(String personId) =>
      _rpcOne('cancel_request_to', {'p_target': personId});

  @override
  Future<void> acceptRequestFrom(String personId) =>
      _rpcOne('accept_request_from', {'p_person': personId});

  // ------------------------------------------------------------- plumbing
  Future<List<Map<String, dynamic>>> _rows(
    String rpc, {
    Map<String, Object?>? params,
  }) async {
    try {
      final result = await _client.rpc(rpc, params: params).timeout(_timeout);
      return _asRows(result);
    } on PostgrestException catch (error) {
      throw _map(error, rpc);
    } on Object catch (error) {
      throw _mapGeneric(error, rpc);
    }
  }

  Future<Map<String, dynamic>> _rpcOne(
    String rpc,
    Map<String, Object?> params,
  ) async {
    try {
      final result = await _client.rpc(rpc, params: params).timeout(_timeout);
      final rows = _asRows(result);
      if (rows.isEmpty) return const <String, dynamic>{};
      return rows.first;
    } on PostgrestException catch (error) {
      throw _map(error, rpc);
    } on Object catch (error) {
      throw _mapGeneric(error, rpc);
    }
  }

  /// `returns table` RPCs arrive as a list of maps; `returns record` ones may
  /// arrive as a single map. Both shapes are normalised here so no caller has
  /// to think about it.
  List<Map<String, dynamic>> _asRows(Object? result) {
    if (result == null) return const <Map<String, dynamic>>[];
    if (result is Map<String, dynamic>) return <Map<String, dynamic>>[result];
    if (result is List) {
      return result.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  AppFailure _map(PostgrestException error, String operation) {
    final code = error.code ?? '';
    final message = error.message;

    if (_missingBackendCodes.contains(code)) {
      _log.warning('backend_missing', data: {'op': operation, 'code': code});
      return const FeatureUnavailableFailure('friends');
    }

    final known = knownActionCodes.firstWhere(
      (token) => message.contains(token),
      orElse: () => '',
    );
    if (known.isNotEmpty) {
      _log.info('action_refused', data: {'op': operation, 'code': known});
      return ServerFailure(statusCode: 409, safeCode: _safeActionCode(known));
    }

    _log.error('postgrest_error', data: {'op': operation, 'code': code});
    return ServerFailure(statusCode: int.tryParse(code));
  }

  AppFailure _mapGeneric(Object error, String operation) {
    _log.error('request_failed', error: error, data: {'op': operation});
    if (error is AppFailure) return error;
    if (error is TimeoutException) {
      return const NetworkFailure(timedOut: true);
    }
    if (error is SocketException) {
      return const NetworkFailure();
    }
    return const ServerFailure();
  }

  /// `safeCode` never contains a Postgres message — only the token we chose.
  String _safeActionCode(String token) => switch (token) {
    'request_not_open' => 'friend_request_not_open',
    'not_your_request' => 'friend_request_not_yours',
    'invalid_target' => 'friend_request_invalid',
    'request_already_open' => 'friend_request_already_open',
    'nothing_to_undo' => 'friend_undo_unavailable',
    _ => 'friend_action_failed',
  };
}
