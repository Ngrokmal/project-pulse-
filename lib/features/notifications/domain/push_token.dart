/// A device's FCM registration token.
///
/// The constraints here mirror the live database exactly
/// (`supabase/migrations/0003_devices_and_tokens.sql`):
///   fcm_tokens_len  → length 20..4096
///   platform        → 'android'
/// A token that fails these rules must never be sent to the server, because the
/// server will reject it and the device would silently stop receiving pushes.
class PushToken {
  const PushToken({required this.value, this.platform = 'android'});

  final String value;
  final String platform;

  static const int minLength = 20;
  static const int maxLength = 4096;

  /// Returns null when [raw] is a usable token, or a human-readable reason.
  static String? validate(String? raw) {
    if (raw == null) return 'No push token was returned by Firebase';
    final value = raw.trim();
    if (value.isEmpty) return 'Push token is empty';
    if (value.length < minLength) {
      return 'Push token is too short (min $minLength characters)';
    }
    if (value.length > maxLength) {
      return 'Push token is too long (max $maxLength characters)';
    }
    // FCM tokens are unpadded base64url + ':' separators, never whitespace.
    if (RegExp(r'\s').hasMatch(value)) return 'Push token contains whitespace';
    return null;
  }

  static PushToken? tryParse(String? raw) =>
      validate(raw) == null ? PushToken(value: raw!.trim()) : null;

  @override
  String toString() => 'PushToken(${value.length} chars, $platform)';
}

/// The outcome of asking the user for notification permission.
enum PushPermission {
  /// Never asked yet — the app must show its rationale first.
  notRequested,

  /// The user allowed notifications.
  granted,

  /// The user declined, but can be asked again.
  denied,

  /// The user declined once already or blocked it in system settings; only the
  /// Android settings screen can undo this.
  permanentlyDenied,

  /// Platform has no notification permission model (e.g. web).
  unsupported;

  bool get canDeliver => this == PushPermission.granted;
}
