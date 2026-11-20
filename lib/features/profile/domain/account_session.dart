/// One row of the owner's "Devices & sessions" list.
///
/// Read from `public.account_device_history` (own rows only, 0003). The app
/// never guesses a device name it was not given: when the server has no label,
/// [label] falls back to the platform word rather than inventing a phone.
class AccountSession {
  const AccountSession({
    required this.deviceId,
    required this.platform,
    required this.firstSeenAt,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String platform;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;

  /// The device this app is running on, when the caller knows its hash.
  bool isCurrent(String? currentDeviceId) =>
      currentDeviceId != null && currentDeviceId == deviceId;

  String get label => switch (platform.toLowerCase()) {
    'android' => 'Android device',
    _ => 'Pulse device',
  };

  /// `Active now` / `Active 2 hours ago` — arithmetic on a stored timestamp.
  String activityLabel(DateTime now) {
    final gap = now.difference(lastSeenAt);
    if (gap.inMinutes < 3) return 'Active now';
    if (gap.inMinutes < 60) return 'Active ${gap.inMinutes} min ago';
    if (gap.inHours < 24) return 'Active ${gap.inHours} h ago';
    final days = gap.inDays;
    if (days == 1) return 'Active yesterday';
    if (days < 30) return 'Active $days days ago';
    return 'Last seen over a month ago';
  }

  factory AccountSession.fromMap(Map<String, dynamic> map) {
    DateTime parse(Object? raw) =>
        DateTime.tryParse(raw as String? ?? '')?.toLocal() ?? DateTime.now();
    return AccountSession(
      deviceId: (map['device_id'] as String?) ?? '',
      platform: (map['platform'] as String?) ?? 'android',
      firstSeenAt: parse(map['first_seen']),
      lastSeenAt: parse(map['last_seen']),
    );
  }
}
