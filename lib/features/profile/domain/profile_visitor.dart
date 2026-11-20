/// One person who opened your card, as `public.profile_visitors()` returns them.
///
/// The row is deliberately small: who, when, how many times. There is no device,
/// no IP, no duration — Pulse records an open, not a person.
class ProfileVisitor {
  const ProfileVisitor({
    required this.id,
    required this.displayName,
    required this.lastSeenAt,
    this.username,
    this.avatarUrl,
    this.visitCount = 1,
  });

  final String id;
  final String displayName;

  /// Without the leading `@`.
  final String? username;
  final String? avatarUrl;

  /// When they last opened the card.
  final DateTime lastSeenAt;

  /// Opens, not visits on different days — the server counts every open.
  final int visitCount;

  String get atHandle =>
      username == null || username!.isEmpty ? '' : '@$username';

  /// `SA` for "Saiful Ahmed" — two letters, never a guess.
  String get initials {
    final words = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final only = words.first;
      return only.substring(0, only.length >= 2 ? 2 : 1).toUpperCase();
    }
    final first = words.first.substring(0, 1);
    final last = words.last.substring(0, 1);
    return '$first$last'.toUpperCase();
  }

  /// `just now`, `12 min ago`, `yesterday`, `4 days ago`, `3 weeks ago`,
  /// `over a month ago` — arithmetic on a stored timestamp, nothing inferred.
  String visitedLabel(DateTime now) {
    final gap = now.difference(lastSeenAt);
    if (gap.isNegative || gap.inSeconds < 60) return 'just now';
    if (gap.inMinutes < 60) return '${gap.inMinutes} min ago';
    if (gap.inHours < 24) return '${gap.inHours} h ago';
    final days = gap.inDays;
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    if (days < 30) {
      final weeks = (days / 7).floor();
      return weeks == 1 ? 'last week' : '$weeks weeks ago';
    }
    if (days < 365) {
      final months = (days / 30).floor();
      return months == 1 ? 'last month' : '$months months ago';
    }
    return 'over a year ago';
  }

  /// `Visited just now` · `Visited 12 min ago · twice` — the only sentence this
  /// row needs.
  String describe(DateTime now) {
    final times = switch (visitCount) {
      <= 1 => '',
      2 => ' · twice',
      _ => ' · $visitCount times',
    };
    return 'Visited ${visitedLabel(now)}$times';
  }

  static ProfileVisitor fromMap(Map<String, dynamic> map) {
    final raw = map['last_seen_at'];
    return ProfileVisitor(
      id: (map['id'] as String?) ?? '',
      displayName: ((map['display_name'] as String?) ?? '').trim().isEmpty
          ? 'Pulse user'
          : (map['display_name'] as String).trim(),
      username: map['username'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      lastSeenAt:
          DateTime.tryParse(raw as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      visitCount: (map['visit_count'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  String toString() => 'ProfileVisitor($displayName, $visitCount, $lastSeenAt)';
}
