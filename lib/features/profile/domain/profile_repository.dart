import 'profile.dart';

/// Contract for profile data. UI/application layers depend on this only.
abstract class ProfileRepository {
  /// Throws typed AppFailure on error; never returns a fabricated profile.
  Future<Profile> fetchMyProfile(String userId);

  Future<Profile> updateMyProfile({
    required String userId,
    required String displayName,
    String? username,
    required String bio,
  });
}
