import '../../presence/domain/presence.dart';

/// One human, as Explore needs them: what to draw, how to greet them, and
/// whether they are around. Presence is the existing value object — Explore
/// does not invent a second idea of "online".
class Person {
  const Person({
    required this.id,
    required this.displayName,
    this.handle,
    this.avatarUrl,
    this.presence = Presence.unknown,
    this.mutualCount = 0,
    this.friendsSince,
  });

  final String id;
  final String displayName;

  /// Lowercase username without the leading `@`.
  final String? handle;
  final String? avatarUrl;
  final Presence presence;

  /// Friends of friends — the number the reference shows under a name.
  final int mutualCount;
  final DateTime? friendsSince;

  String get atHandle => handle == null || handle!.isEmpty ? '' : '@$handle';

  /// `NS` for "Nusrat Sultana" — never more than two letters, never a guess.
  String get initials {
    final words = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
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

  /// Stable seed for the avatar gradient: the id, so a person keeps their
  /// colour between screens and rebuilds.
  String get gradientSeed => id.isEmpty ? displayName : id;

  Person copyWith({
    Presence? presence,
    int? mutualCount,
    DateTime? friendsSince,
  }) {
    return Person(
      id: id,
      displayName: displayName,
      handle: handle,
      avatarUrl: avatarUrl,
      presence: presence ?? this.presence,
      mutualCount: mutualCount ?? this.mutualCount,
      friendsSince: friendsSince ?? this.friendsSince,
    );
  }
}
