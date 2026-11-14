import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../data/supabase_profile_repository.dart';
import '../domain/profile.dart';
import '../domain/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure(
      'Supabase is not configured for this build.',
    );
  }
  return SupabaseProfileRepository(Supabase.instance.client);
});

/// Loads the signed-in user's profile. Empty/error states are explicit.
class ProfileController extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return null;
    return ref.read(profileRepositoryProvider).fetchMyProfile(auth.user.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final auth = ref.read(authControllerProvider);
      if (auth is! AuthSignedIn) return null;
      return ref.read(profileRepositoryProvider).fetchMyProfile(auth.user.id);
    });
  }

  /// Returns a typed failure to display, or null on success.
  Future<AppFailure?> save({
    required String displayName,
    String? username,
    required String bio,
  }) async {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthSignedIn) {
      return const AuthFailure('Your session expired. Please log in again.');
    }
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .updateMyProfile(
            userId: auth.user.id,
            displayName: displayName,
            username: username,
            bio: bio,
          );
      state = AsyncData(updated);
      return null;
    } on AppFailure catch (f) {
      return f;
    } catch (_) {
      return const ServerFailure();
    }
  }
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, Profile?>(ProfileController.new);
