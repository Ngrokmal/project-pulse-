import 'profile_privacy.dart';

/// A PULSE profile — mirrors public.profiles (migrations/0001 + 0012).
///
/// Everything here is stored. Nothing is measured, inferred or counted: the
/// card this domain feeds has no statistics on it by design.
class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    this.username,
    this.bio = '',
    this.avatarUrl,
    this.coverUrl,
    this.joinedAt,
    this.statusText = '',
    this.whereText = '',
    this.timezone,
    this.utcOffsetMinutes,
    this.labels = const <String>[],
    this.privacy = ProfilePrivacy.defaults,
  });

  final String id;
  final String displayName;
  final String? username;
  final String bio;
  final String? avatarUrl;
  final String? coverUrl;
  final DateTime? joinedAt;

  /// The status line, typed by its owner. Empty means the tile disappears.
  final String statusText;

  /// The place, typed by its owner. Empty means the row disappears — never
  /// filled in from GPS, an IP address or a timezone guess.
  final String whereText;

  /// The zone label the owner's device reported when they saved (for example
  /// "Dhaka"), plus the offset in minutes. Together they render `6:11 PM · Dhaka`
  /// with arithmetic only.
  final String? timezone;
  final int? utcOffsetMinutes;

  /// Up to [maxLabels] short labels — "Family", "Work" — shown under Kept close.
  final List<String> labels;

  final ProfilePrivacy privacy;

  // Guard rails, matching the CHECK constraints in 0012 exactly.
  static const int statusMax = 80;
  static const int whereMax = 40;
  static const int labelMax = 20;
  static const int maxLabels = 6;

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
    statusText: (map['status_text'] as String?) ?? '',
    whereText: (map['where_text'] as String?) ?? '',
    timezone: map['timezone'] as String?,
    utcOffsetMinutes: (map['utc_offset_minutes'] as num?)?.toInt(),
    labels: _parseLabels(map['labels']),
    privacy: ProfilePrivacy.fromMap(map),
  );

  static List<String> _parseLabels(Object? raw) {
    if (raw is! List) return const <String>[];
    return List<String>.unmodifiable(
      raw
          .whereType<String>()
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty)
          .take(maxLabels),
    );
  }

  Profile copyWith({
    String? displayName,
    String? username,
    String? bio,
    bool clearUsername = false,
    String? statusText,
    String? whereText,
    String? timezone,
    int? utcOffsetMinutes,
    List<String>? labels,
    ProfilePrivacy? privacy,
  }) => Profile(
    id: id,
    displayName: displayName ?? this.displayName,
    username: clearUsername ? null : (username ?? this.username),
    bio: bio ?? this.bio,
    avatarUrl: avatarUrl,
    coverUrl: coverUrl,
    joinedAt: joinedAt,
    statusText: statusText ?? this.statusText,
    whereText: whereText ?? this.whereText,
    timezone: timezone ?? this.timezone,
    utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
    labels: labels ?? this.labels,
    privacy: privacy ?? this.privacy,
  );

  /// Rules must match the DB constraints in 0001 and 0012 exactly.
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

  static String? validateStatus(String input) {
    if (input.trim().length > statusMax) {
      return 'Use at most $statusMax characters';
    }
    return null;
  }

  static String? validateWhere(String input) {
    if (input.trim().length > whereMax) {
      return 'Use at most $whereMax characters';
    }
    return null;
  }

  static String? validateLabel(String input) {
    final v = input.trim();
    if (v.isEmpty) return 'A label needs a name';
    if (v.length > labelMax) return 'Use at most $labelMax characters';
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

  /// `@saiful`, or null when no handle has been chosen yet.
  String? get handle {
    final name = username?.trim() ?? '';
    return name.isEmpty ? null : '@$name';
  }

  /// The one link that opens this card.
  String? get shareLink {
    final name = username?.trim() ?? '';
    return name.isEmpty ? null : 'pulse.app/@$name';
  }

  /// What "Message" should say when there is nobody to message yet.
  String get givenName {
    final clean = displayName.trim();
    if (clean.isEmpty) return 'This person';
    return clean.split(RegExp(r'\s+')).first;
  }
}
