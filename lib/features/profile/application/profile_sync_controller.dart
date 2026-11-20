import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the card knows about its own connection.
///
/// The profile screen is honest about three states and no more: everything is
/// on the server, some switches are waiting for a connection, or we are reading
/// a cached copy. Nothing else is inferred.
class ProfileSyncState {
  const ProfileSyncState({this.offline = false, this.pending = 0, this.note});

  /// The last read came from the cache because the network did not answer.
  final bool offline;

  /// How many settings changes are queued for the next successful call.
  final int pending;

  /// Optional one-line explanation, already user-safe.
  final String? note;

  bool get isClean => !offline && pending == 0;

  ProfileSyncState copyWith({
    bool? offline,
    int? pending,
    String? note,
    bool clearNote = false,
  }) => ProfileSyncState(
    offline: offline ?? this.offline,
    pending: pending ?? this.pending,
    note: clearNote ? null : (note ?? this.note),
  );
}

class ProfileSyncController extends Notifier<ProfileSyncState> {
  @override
  ProfileSyncState build() => const ProfileSyncState();

  void markOnline() {
    if (state.offline) state = state.copyWith(offline: false);
  }

  void markOffline(String note) =>
      state = state.copyWith(offline: true, note: note);

  void setPending(int pending) => state = state.copyWith(pending: pending);

  void setNote(String? note) => state = note == null
      ? state.copyWith(clearNote: true)
      : state.copyWith(note: note);
}

final profileSyncProvider =
    NotifierProvider<ProfileSyncController, ProfileSyncState>(
      ProfileSyncController.new,
    );
