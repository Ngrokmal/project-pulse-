import '../../presence/domain/presence.dart';
import '../domain/friend_request.dart';
import '../domain/friend_state.dart';
import '../domain/people_search.dart';
import '../domain/person.dart';

/// Postgres rows → domain objects, in one place.
///
/// The RPCs in `0010_friends.sql` return the same column names on purpose, so a
/// single mapper serves search, incoming, sent and friends. Anything missing is
/// treated as absent rather than invented — a null `last_seen_at` is
/// [Presence.unknown], never "online".
class ExploreRowMapper {
  const ExploreRowMapper._();

  static String _text(Object? value) => value is String ? value : '';

  static String? _nullableText(Object? value) {
    if (value is String) return value.isEmpty ? null : value;
    return null;
  }

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _time(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static Person person(Map<String, dynamic> row, {String idKey = 'person_id'}) {
    final id = _text(row[idKey]);
    return Person(
      id: id,
      displayName: _text(row['display_name']),
      handle: _nullableText(row['username']),
      // A hidden photo is not delivered anywhere; every face in the app obeys
      // the same column.
      avatarUrl: row['photo_visible'] == false
          ? null
          : _nullableText(row['avatar_url']),
      presence: Presence(lastSeenAt: _time(row['last_seen_at'])),
      mutualCount: _int(row['mutual_count']),
      friendsSince: _time(row['friends_since']),
    );
  }

  static FriendRequest request(Map<String, dynamic> row) => FriendRequest(
    id: _text(row['request_id']),
    person: person(row),
    sentAt: _time(row['sent_at']) ?? DateTime.now(),
  );

  static SearchHit hit(Map<String, dynamic> row) => SearchHit(
    person: person(
      row,
      idKey: row.containsKey('person_id') ? 'person_id' : 'id',
    ),
    state: FriendState.parse(_nullableText(row['friend_state'])),
    score: _int(row['score']).clamp(0, 100),
  );
}
