import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../data/supabase_profile_repository.dart';
import '../domain/profile.dart';
import '../domain/profile_media.dart';
import '../domain/profile_privacy.dart';
import '../domain/profile_repository.dart';
import '../domain/profile_time.dart';

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
  ///
  /// [statusText], [whereText] and the zone are optional so the older plain edit
  /// screen keeps working; the card sheet always passes them.
  Future<AppFailure?> save({
    required String displayName,
    String? username,
    required String bio,
    String? statusText,
    String? whereText,
    List<String>? labels,
    bool captureZone = false,
  }) async {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthSignedIn) {
      return const AuthFailure('Your session expired. Please log in again.');
    }

    // The zone is captured from *this* device at the moment of saving. It is a
    // stored number, not a lookup: the card can then show local time without
    // ever asking where anyone is.
    final zone = captureZone ? ProfileTime.fromLocalDevice() : null;

    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .updateMyProfile(
            userId: auth.user.id,
            displayName: displayName,
            username: username,
            bio: bio,
            statusText: statusText,
            whereText: whereText,
            labels: labels,
            timezone: zone?.label,
            utcOffsetMinutes: zone?.offsetMinutes,
          );
      // Keep whatever the database could not store (a half-migrated project)
      // visible in the UI rather than silently discarding the user's words.
      state = AsyncData(
        updated.copyWith(
          statusText: statusText ?? updated.statusText,
          whereText: whereText ?? updated.whereText,
          labels: labels ?? updated.labels,
        ),
      );
      return null;
    } on AppFailure catch (f) {
      return f;
    } catch (_) {
      return const ServerFailure();
    }
  }

  /// One privacy switch. Optimistic, and rolled back if the write fails.
  Future<AppFailure?> setPrivacy(PrivacyField field, bool value) async {
    final auth = ref.read(authControllerProvider);
    final current = state.value;
    if (auth is! AuthSignedIn || current == null) {
      return const AuthFailure('Your session expired. Please log in again.');
    }

    final before = current;
    state = AsyncData(current.copyWith(privacy: current.privacy.withValue(field, value)));
    try {
      final saved = await ref
          .read(profileRepositoryProvider)
          .updatePrivacy(userId: auth.user.id, field: field, value: value);
      state = AsyncData(before.copyWith(privacy: saved));
      return null;
    } on AppFailure catch (f) {
      state = AsyncData(before);
      return f;
    } catch (_) {
      state = AsyncData(before);
      return const ServerFailure();
    }
  }

  /// Adds a Kept-close label (max six, deduplicated, each at most 20 chars).
  Future<AppFailure?> addLabel(String label) async {
    final current = state.value;
    if (current == null) return const ServerFailure();
    final error = Profile.validateLabel(label);
    if (error != null) return ValidationFailure('label', error);
    if (current.labels.length >= Profile.maxLabels) {
      return const ValidationFailure(
        'label',
        'Six labels is the whole shelf — remove one first.',
      );
    }
    final clean = label.trim();
    if (current.labels.any((l) => l.toLowerCase() == clean.toLowerCase())) {
      return null;
    }
    return _writeLabels(<String>[...current.labels, clean]);
  }

  Future<AppFailure?> removeLabel(String label) async {
    final current = state.value;
    if (current == null) return const ServerFailure();
    return _writeLabels(
      current.labels.where((l) => l != label).toList(growable: false),
    );
  }

  Future<AppFailure?> _writeLabels(List<String> labels) async {
    final current = state.value;
    final auth = ref.read(authControllerProvider);
    if (current == null || auth is! AuthSignedIn) {
      return const AuthFailure('Your session expired. Please log in again.');
    }
    state = AsyncData(current.copyWith(labels: labels));
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateMyProfile(
            userId: auth.user.id,
            displayName: current.displayName,
            username: current.username,
            bio: current.bio,
            labels: labels,
            statusText: current.statusText,
            whereText: current.whereText,
          );
      return null;
    } on AppFailure catch (f) {
      state = AsyncData(current);
      return f;
    } catch (_) {
      state = AsyncData(current);
      return const ServerFailure();
    }
  }
}

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, Profile?>(ProfileController.new);

/// The Media lens: this account's own recent attachments.
///
/// Kept separate from the profile row so a slow gallery never delays the card,
/// and `autoDispose` so leaving the lens releases the images.
final profileMediaProvider = FutureProvider.autoDispose<List<ProfileMedia>>((
  ref,
) {
  return ref.watch(profileRepositoryProvider).recentMedia(limit: 6);
});
