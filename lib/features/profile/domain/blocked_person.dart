/// One row of the Blocked people page.
///
/// Read from `public.blocked_people()` (0014): the caller's own blocks, joined
/// to the person behind each one. There is no "they blocked you" flag and no
/// count on this table — a block is a fact one person wrote, and this is the
/// list of the facts *you* wrote.
class BlockedPerson {
  const BlockedPerson({
    required this.id,
    required this.displayName,
    this.username,
    this.avatarUrl,
    required this.blockedAt,
  });

  final String id;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final DateTime blockedAt;

  String get initials {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters1;
    return '${parts.first.characters1}${parts.last.characters1}';
  }

  /// `Blocked today` / `Blocked 3 days ago` — arithmetic on a stored timestamp,
  /// never a guess about why.
  String blockedLabel(DateTime now) {
    final gap = now.difference(blockedAt);
    if (gap.inMinutes < 2) return 'Blocked just now';
    if (gap.inMinutes < 60) return 'Blocked ${gap.inMinutes} min ago';
    if (gap.inHours < 24) return 'Blocked ${gap.inHours} h ago';
    final days = gap.inDays;
    if (days == 1) return 'Blocked yesterday';
    if (days < 30) return 'Blocked $days days ago';
    if (days < 365) return 'Blocked ${(days / 30).floor()} months ago';
    return 'Blocked over a year ago';
  }

  factory BlockedPerson.fromMap(Map<String, dynamic> map) => BlockedPerson(
    id: (map['id'] as String?) ?? '',
    displayName: (map['display_name'] as String?)?.trim().isNotEmpty == true
        ? (map['display_name'] as String).trim()
        : 'Pulse user',
    username: map['username'] as String?,
    avatarUrl: map['avatar_url'] as String?,
    blockedAt:
        DateTime.tryParse((map['blocked_at'] as String?) ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

extension on String {
  String get characters1 => isEmpty ? '?' : substring(0, 1).toUpperCase();
}
