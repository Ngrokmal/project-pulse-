/// The 50 % letter rule, in Dart.
///
/// This is the same algorithm as `public.friend_match_score()` in
/// `0010_friends.sql` — exact → 100, prefix → 95, substring → 88, otherwise the
/// share of the typed letters that survived a longest-common-subsequence walk,
/// and only when that share is at least half **and** at least three letters.
///
/// Two copies exist on purpose: the server scores the whole network in one
/// indexed pass, and the client needs to re-rank and to explain a score
/// ("67 % match") without another round trip. `test/explore_people_match_test.dart`
/// holds the table both are checked against, so they cannot drift apart silently.
class PeopleMatch {
  const PeopleMatch._();

  /// Nothing below half of the typed letters is ever shown.
  static const int minimumScore = 50;

  /// Three letters is the floor for the fuzzy rule, so a two- or three-letter
  /// query cannot "match" half the network.
  static const int minimumLetters = 3;

  /// Letters and digits only, lowercased. `@`, spaces and punctuation are
  /// noise for matching but matter to the eye, so they are dropped here only.
  static String normalise(String input) =>
      input.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');

  /// Length of the longest common subsequence of [a] and [b].
  static int lcsLength(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final left = a.length > 64 ? a.substring(0, 64) : a;
    final right = b.length > 64 ? b.substring(0, 64) : b;

    var previous = List<int>.filled(right.length + 1, 0);
    var current = List<int>.filled(right.length + 1, 0);

    for (var i = 1; i <= left.length; i++) {
      current[0] = 0;
      final char = left[i - 1];
      for (var j = 1; j <= right.length; j++) {
        current[j] = char == right[j - 1]
            ? previous[j - 1] + 1
            : (previous[j] > current[j - 1] ? previous[j] : current[j - 1]);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[right.length];
  }

  /// 0…100. Mirrors `friend_match_score(q, name, handle)`.
  static int score({
    required String query,
    required String displayName,
    String? handle,
  }) {
    final needle = normalise(query);
    if (needle.length < 2) return 0;

    var best = 0;
    for (final field in <String>[
      normalise(displayName),
      normalise(handle ?? ''),
    ]) {
      if (field.isEmpty) continue;

      if (field == needle) {
        if (best < 100) best = 100;
      } else if (field.startsWith(needle)) {
        if (best < 95) best = 95;
      } else if (field.contains(needle)) {
        if (best < 88) best = 88;
      } else {
        final hit = lcsLength(needle, field);
        final coverage = hit / needle.length;
        final floor = needle.length < minimumLetters
            ? needle.length
            : minimumLetters;
        if (coverage >= 0.5 && hit >= floor) {
          final fuzzy = (28 + coverage * 58).round();
          if (fuzzy > best) best = fuzzy;
        }
      }
    }
    return best;
  }

  static bool passes(int score) => score >= minimumScore;
}
