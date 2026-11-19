import 'person.dart';

/// A pending ask, in either direction. `person` is the *other* party: the
/// requester for an incoming card, the addressee for a sent one.
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.person,
    required this.sentAt,
  });

  final String id;
  final Person person;
  final DateTime sentAt;

  FriendRequest copyWith({Person? person}) =>
      FriendRequest(id: id, person: person ?? this.person, sentAt: sentAt);
}
