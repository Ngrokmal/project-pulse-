class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.status,
    required this.canSendMessages,
    required this.canStartCalls,
    required this.canChangeProfilePhoto,
    this.endsAt,
  });

  final String id;
  final String email;
  final String displayName;
  final String status;
  final bool canSendMessages;
  final bool canStartCalls;
  final bool canChangeProfilePhoto;
  final DateTime? endsAt;
  bool get isSuspended => status == 'suspended';
  bool get canManageSuspension => status == 'active' || isSuspended;

  factory ManagedUser.fromMap(Map<String, dynamic> row) => ManagedUser(
    id: row['id'] as String,
    email: row['email'] as String? ?? '',
    displayName: row['display_name'] as String? ?? '',
    status: row['status'] as String? ?? 'active',
    canSendMessages: row['can_send_messages'] as bool? ?? true,
    canStartCalls: row['can_start_calls'] as bool? ?? true,
    canChangeProfilePhoto: row['can_change_profile_photo'] as bool? ?? true,
    endsAt: row['ends_at'] == null
        ? null
        : DateTime.tryParse(row['ends_at'].toString()),
  );
}

abstract interface class AdminRepository {
  Future<bool> isAdmin();
  Future<List<ManagedUser>> users({String query = '', int offset = 0});
  Future<void> setControl(String userId, String control, bool enabled);
  Future<void> setSuspension(String userId, bool suspended, {DateTime? until});
  Future<void> setErrorMessage(String code, String message);
}
