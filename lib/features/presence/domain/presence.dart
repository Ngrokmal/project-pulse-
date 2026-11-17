/// Presence, as one honest value: the server's `user_presence.last_seen_at`.
///
/// There is no "online" flag in the database and there should not be one — a
/// crashed phone would stay "online" forever. Online is *derived*: someone is
/// online when their last heartbeat is inside [onlineWindow]. The app beats
/// every 30 s, so the window is three beats wide.
class Presence {
  const Presence({this.lastSeenAt});

  final DateTime? lastSeenAt;

  static const Duration onlineWindow = Duration(seconds: 90);

  static const Presence unknown = Presence();

  bool get isKnown => lastSeenAt != null;

  bool isOnlineAt(DateTime now) {
    final seen = lastSeenAt;
    if (seen == null) return false;
    final age = now.difference(seen);
    return age >= -const Duration(seconds: 5) && age < onlineWindow;
  }

  /// `online`, or how long ago — never an invented status.
  String label(DateTime now) {
    if (isOnlineAt(now)) return 'online';
    final seen = lastSeenAt;
    if (seen == null) return 'offline';
    return 'last seen ${_ago(now.difference(seen))}';
  }

  /// The short form for a compact header: `online`, `last seen 5m ago`.
  static String _ago(Duration age) {
    if (age.isNegative) return 'just now';
    if (age.inSeconds < 60) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    if (age.inDays == 1) return 'yesterday';
    if (age.inDays < 7) return '${age.inDays}d ago';
    if (age.inDays < 365) {
      final weeks = (age.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    }
    final years = (age.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
  }
}
