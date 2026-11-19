import 'friend_request.dart';
import 'friend_state.dart';
import 'people_search.dart';
import 'person.dart';

/// What Explore needs from the backend, in its own words.
///
/// Reads are lists of domain objects; writes return the state the server ended
/// up in, so the UI never has to guess whether a tap "worked".
abstract interface class ExploreRepository {
  /// People who asked me, newest first.
  Future<List<FriendRequest>> incomingRequests();

  /// People I asked, newest first.
  Future<List<FriendRequest>> sentRequests();

  /// My circle, newest friendship first.
  Future<List<Person>> friends();

  /// The number on the Friends segment. Asked for separately because the list
  /// itself is capped, and a count must never be a lie about the whole set.
  Future<int> friendsCount();

  /// One explicit search. Never called per keystroke.
  Future<PeopleSearch> searchPeople(String query, {int limit = 20});

  /// The closest names that did NOT clear the 50 % floor. Only called when a
  /// search came back empty, so a normal search never pays for it.
  Future<List<SearchHit>> nearMisses(String query, {int limit = 2});

  /// How many profiles exist, for the "of 4,208" line.
  Future<int> networkSize();

  /// Sends an ask and returns the resulting state — which may be
  /// [FriendState.friend] when the other person had already asked me.
  Future<FriendState> sendRequest(String personId);

  Future<void> acceptRequest(String requestId);

  Future<void> declineRequest(String requestId);

  Future<void> cancelRequest(String requestId);

  /// Walks a decline back (the toast's Undo).
  Future<void> undoDecline(String requestId);

  /// The search sheet knows a person, not a request id: cancel my open ask to
  /// them without first looking the row up.
  Future<void> cancelRequestTo(String personId);

  /// Accept the open ask that [personId] sent me, again by person.
  Future<void> acceptRequestFrom(String personId);
}
