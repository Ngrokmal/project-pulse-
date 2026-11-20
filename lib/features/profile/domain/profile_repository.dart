import 'profile.dart';
import 'profile_media.dart';
import 'profile_privacy.dart';

/// Contract for profile data. UI/application layers depend on this only.
abstract class ProfileRepository {
  /// Throws typed AppFailure on error; never returns a fabricated profile.
  Future<Profile> fetchMyProfile(String userId);

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

  /// The account's own recent attachments, newest first — the Media lens.
  Future<List<ProfileMedia>> recentMedia({int limit});
}
