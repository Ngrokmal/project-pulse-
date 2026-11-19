import 'friend_state.dart';
import 'person.dart';

/// One row of a search answer: who, how we know them, and how well they matched.
class SearchHit {
  const SearchHit({
    required this.person,
    required this.state,
    required this.score,
  });

  final Person person;
  final FriendState state;

  /// 0…100, from the 50 % rule. 100 means the name or handle is exactly what
  /// was typed, so the meter is only drawn when this is below 100.
  final int score;

  bool get isExact => score >= 100;
}

/// The answer to one explicit submit. `query` is kept so the sheet can say
/// "3 people match “nus”" even if the field has been edited since.
class PeopleSearch {
  const PeopleSearch({
    required this.query,
    required this.hits,
    required this.networkSize,
  });

  final String query;
  final List<SearchHit> hits;

  /// Size of the searched population, for the honest "of 4,208" line.
  final int networkSize;

  bool get isEmpty => hits.isEmpty;

  static const PeopleSearch none = PeopleSearch(
    query: '',
    hits: <SearchHit>[],
    networkSize: 0,
  );
}
