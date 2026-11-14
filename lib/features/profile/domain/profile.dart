/// A PULSE profile — mirrors public.profiles (migrations/0001).
class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    this.username,
    this.bio = '',
    this.avatarUrl,
    this.coverUrl,
    this.joinedAt,
  });

  final String id;
  final String displayName;
  final String? username;
  final String bio;
  final String? avatarUrl;
  final String? coverUrl;
  final DateTime? joinedAt;

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
    id: map['id'] as String,
    displayName: (map['display_name'] as String?) ?? '',
    username: map['username'] as String?,
    bio: (map['bio'] as String?) ?? '',
    avatarUrl: map['avatar_url'] as String?,
    coverUrl: map['cover_url'] as String?,
    joinedAt: map['joined_at'] == null
        ? null
        : DateTime.tryParse(map['joined_at'] as String)?.toLocal(),
  );

  Profile copyWith({
    String? displayName,
    String? username,
    String? bio,
    bool clearUsername = false,
  }) => Profile(
    id: id,
    displayName: displayName ?? this.displayName,
    username: clearUsername ? null : (username ?? this.username),
    bio: bio ?? this.bio,
    avatarUrl: avatarUrl,
    coverUrl: coverUrl,
    joinedAt: joinedAt,
  );

  /// Rules must match the DB constraints in 0001_profiles.sql exactly.
  static final RegExp usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');
  static const int displayNameMax = 60;
  static const int bioMax = 200;

  static String normalizeUsername(String input) => input.trim().toLowerCase();

  static String? validateDisplayName(String input) {
    final v = input.trim();
    if (v.isEmpty) return 'Display name is required';
    if (v.length > displayNameMax) {
      return 'Use at most $displayNameMax characters';
    }
    return null;
  }

  static String? validateUsername(String input) {
    final v = input.trim();
    if (v.isEmpty) return null; // optional
    if (!usernamePattern.hasMatch(normalizeUsername(v))) {
      return '3-24 characters, lowercase letters, numbers or underscore';
    }
    return null;
  }

  static String? validateBio(String input) {
    if (input.length > bioMax) return 'Use at most $bioMax characters';
    return null;
  }

  String get initials {
    final source = displayName.trim().isEmpty
        ? (username ?? '?')
        : displayName.trim();
    final parts = source
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    String first(String s) => s.substring(0, 1).toUpperCase();
    if (parts.length == 1) {
      return first(parts.first);
    }
    return first(parts.first) + first(parts.last);
  }
}
