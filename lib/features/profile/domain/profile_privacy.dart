/// The five switches on the Profile screen, as one honest value.
///
/// Every field is stored on `public.profiles` (0012) and is the owner's own
/// decision — nothing here is derived from behaviour.
enum PrivacyField {
  lastSeen('last_seen_visible', 'Last seen & online'),
  readReceipts('read_receipts', 'Read receipts'),
  photoVisible('photo_visible', 'Profile photo'),
  notifications('push_notifications', 'Notifications'),
  chatLock('chat_lock', 'Chat lock');

  const PrivacyField(this.column, this.label);

  /// The column this switch writes to.
  final String column;
  final String label;
}

class ProfilePrivacy {
  const ProfilePrivacy({
    this.lastSeenVisible = true,
    this.readReceipts = false,
    this.photoVisible = true,
    this.notifications = true,
    this.chatLock = false,
  });

  final bool lastSeenVisible;
  final bool readReceipts;
  final bool photoVisible;
  final bool notifications;
  final bool chatLock;

  /// What a brand-new account gets — matches the column defaults in 0012.
  static const ProfilePrivacy defaults = ProfilePrivacy();

  factory ProfilePrivacy.fromMap(Map<String, dynamic> map) => ProfilePrivacy(
    lastSeenVisible: map['last_seen_visible'] as bool? ?? true,
    readReceipts: map['read_receipts'] as bool? ?? false,
    photoVisible: map['photo_visible'] as bool? ?? true,
    notifications: map['push_notifications'] as bool? ?? true,
    chatLock: map['chat_lock'] as bool? ?? false,
  );

  bool valueOf(PrivacyField field) => switch (field) {
    PrivacyField.lastSeen => lastSeenVisible,
    PrivacyField.readReceipts => readReceipts,
    PrivacyField.photoVisible => photoVisible,
    PrivacyField.notifications => notifications,
    PrivacyField.chatLock => chatLock,
  };

  ProfilePrivacy withValue(PrivacyField field, bool value) => ProfilePrivacy(
    lastSeenVisible: field == PrivacyField.lastSeen ? value : lastSeenVisible,
    readReceipts: field == PrivacyField.readReceipts ? value : readReceipts,
    photoVisible: field == PrivacyField.photoVisible ? value : photoVisible,
    notifications: field == PrivacyField.notifications ? value : notifications,
    chatLock: field == PrivacyField.chatLock ? value : chatLock,
  );

  /// The single column write a toggle needs.
  Map<String, Object?> toColumnMap(PrivacyField field) => <String, Object?>{
    field.column: valueOf(field),
  };

  Map<String, Object?> toMap() => <String, Object?>{
    for (final field in PrivacyField.values) field.column: valueOf(field),
  };
}
