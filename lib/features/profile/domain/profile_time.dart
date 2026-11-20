/// Local time, computed from a stored offset — never from a location.
///
/// `profiles.utc_offset_minutes` is captured from the owner's own phone the
/// moment they save their card, and `profiles.timezone` is the label that phone
/// reports (for example "Dhaka"). Rendering is therefore pure arithmetic on two
/// numbers the owner can see, which is why the card can say
/// "6:11 PM · Dhaka" without knowing anything about where anyone is.
class ProfileTime {
  const ProfileTime({required this.offsetMinutes, this.label});

  final int offsetMinutes;
  final String? label;

  /// The honest fallback: the viewer's own offset, used only when the profile
  /// has never stored one (a brand-new account that has not saved yet).
  static ProfileTime fromLocalDevice([DateTime? now]) {
    final moment = now ?? DateTime.now();
    return ProfileTime(
      offsetMinutes: moment.timeZoneOffset.inMinutes,
      label: _cleanZoneName(moment.timeZoneName),
    );
  }

  static ProfileTime? fromProfile({int? offsetMinutes, String? label}) {
    if (offsetMinutes == null) return null;
    final clean = (label ?? '').trim();
    return ProfileTime(
      offsetMinutes: offsetMinutes,
      label: clean.isEmpty ? null : clean,
    );
  }

  /// `6:11 PM`, in the profile's own zone.
  String clockAt(DateTime nowUtc) {
    final local = nowUtc.toUtc().add(Duration(minutes: offsetMinutes));
    final hour24 = local.hour;
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${hour24 < 12 ? 'AM' : 'PM'}';
  }

  /// The one line the tile shows: `6:11 PM · Dhaka`.
  String displayAt(DateTime nowUtc) {
    final time = clockAt(nowUtc);
    final zone = label;
    return zone == null ? time : '$time · $zone';
  }

  /// `+06:00`, for the edit sheet so the owner can see what is stored.
  String get offsetLabel {
    final sign = offsetMinutes < 0 ? '-' : '+';
    final abs = offsetMinutes.abs();
    final hours = (abs ~/ 60).toString().padLeft(2, '0');
    final minutes = (abs % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  /// Android reports things like "GMT+06:00"; iOS reports "GMT+6". Neither is a
  /// city, so they are tidied into something a person can read, and never
  /// invented into a place name.
  static String? _cleanZoneName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('GMT') || trimmed.startsWith('UTC')) return null;
    return trimmed;
  }
}
