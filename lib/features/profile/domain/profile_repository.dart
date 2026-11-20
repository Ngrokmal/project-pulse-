import 'dart:typed_data';

import 'account_session.dart';
import 'blocked_person.dart';
import 'profile.dart';
import 'profile_media.dart';
import 'profile_visitor.dart';
import 'profile_privacy.dart';
import 'safety_action.dart';

/// Contract for profile data. UI/application layers depend on this only.
abstract class ProfileRepository {
  /// Throws typed AppFailure on error; never returns a fabricated profile.
  Future<Profile> fetchMyProfile(String userId);

  /// Somebody else's card, read exactly as the server is willing to give it.
  ///
  /// A missing profile is [ServerFailure], never an empty card: a visitor page
  /// that quietly invents a person is worse than one that says it could not.
  Future<Profile> fetchProfile(String userId);

  /// Writes the whole card in one round trip.
  ///
  /// [statusText], [whereText], [timezone] and [utcOffsetMinutes] are optional
  /// so older call sites (the plain edit screen) keep working unchanged.
  Future<Profile> updateMyProfile({
    required String userId,
    required String displayName,
    String? username,
    required String bio,
    String? statusText,
    String? whereText,
    String? timezone,
    int? utcOffsetMinutes,
    List<String>? labels,
  });

  /// One switch, one column. Returns the row as it now is.
  Future<ProfilePrivacy> updatePrivacy({
    required String userId,
    required PrivacyField field,
    required bool value,
  });

  /// A partial write of column → value. The offline queue drains through this:
  /// a change made on a train is one `update`, not a whole card rewrite that
  /// could clobber a status typed on another device.
  Future<void> patchProfile({
    required String userId,
    required Map<String, Object?> values,
  });

  /// The account's own recent attachments, newest first — the Media lens.
  Future<List<ProfileMedia>> recentMedia({int limit});

  // ─────────────────────────────────────────────────────────────── photo

  /// Uploads a square JPEG/PNG and points `profiles.avatar_url` at it.
  /// Returns the public URL the rest of the app should render.
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String mimeType,
    required DateTime takenAt,
  });

  /// Clears the column and, best effort, deletes the object it pointed at.
  Future<void> removeAvatar({required String userId, String? existingUrl});

  // ─────────────────────────────────────────────────────────── account

  /// The owner's own devices, newest activity first.
  Future<List<AccountSession>> sessions();

  /// Ends every other session. The current device stays signed in.
  Future<void> signOutOtherSessions();

  // ──────────────────────────────────────────────────────────── safety

  Future<void> blockUser(String targetUserId);
  Future<void> unblockUser(String targetUserId);

  /// True when this account has blocked [targetUserId].
  Future<bool> hasBlocked(String targetUserId);

  /// Everyone this account has blocked, newest first (0014).
  Future<List<BlockedPerson>> blockedPeople();

  Future<void> reportUser({
    required String targetUserId,
    required ReportReason reason,
  });

  // ──────────────────────────────────────────────────────── profile views

  /// Records that this account opened [targetUserId]'s card (0015).
  ///
  /// Best effort by design: a card must open even if the server is busy, so the
  /// caller ignores a failure rather than showing it.
  Future<void> recordProfileVisit(String targetUserId);

  /// Who opened this account's card, newest first.
  Future<List<ProfileVisitor>> profileVisitors({int limit});

  /// Clears the direct conversation with [otherUserId] for this account only.
  /// Silent when there is no conversation yet — clearing nothing is not an
  /// error.
  Future<void> clearChatWith(String otherUserId);
}
