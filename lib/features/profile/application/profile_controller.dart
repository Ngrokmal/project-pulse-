import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/auth_controller.dart';
import '../data/profile_local_store.dart';
import '../data/supabase_profile_repository.dart';
import '../domain/pending_write.dart';
import '../domain/profile.dart';
import '../domain/profile_media.dart';
import '../domain/profile_privacy.dart';
import '../domain/profile_repository.dart';
import '../domain/profile_time.dart';
import 'profile_sync_controller.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure(
      'Supabase is not configured for this build.',
    );
  }
  return SupabaseProfileRepository(Supabase.instance.client);
});

/// Loads the signed-in user's profile. Empty/error states are explicit.
///
/// Offline is a first-class state here, not a failure: a cached row is served,
/// the sync flag says so, and any settings flipped while disconnected are
/// queued in the outbox and drained on the next successful call.
class ProfileController extends AsyncNotifier<Profile?> {
  static final _log = AppLogger('profile.controller');
  static const _uuid = Uuid();

  ProfileLocalStore? get _store => ProfileLocalStore.instance;

  @override
  Future<Profile?> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return null;
    return _load(auth.user.id);
  }

  Future<Profile?> _load(String userId) async {
    final repo = ref.read(profileRepositoryProvider);
    final store = _store;
    final sync = ref.read(profileSyncProvider.notifier);

    // Anything queued from a previous session goes first, so the row we read
    // below already carries the user's own decisions.
    await flushPending(silent: true);

    try {
      final profile = await repo.fetchMyProfile(userId);
      store?.cacheProfile(profile);
      sync.markOnline();
      sync.setPending(store?.pending(userId).length ?? 0);
      return profile;
    } on NetworkFailure catch (failure) {
      final cached = store?.cachedProfile(userId);
      if (cached == null) rethrow;
      _log.info('profile_served_from_cache');
      sync.markOffline(failure.userMessage);
      sync.setPending(store?.pending(userId).length ?? 0);
      return cached;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final auth = ref.read(authControllerProvider);
      if (auth is! AuthSignedIn) return null;
      return _load(auth.user.id);
    });
  }

  /// Writes the queued column changes, oldest first. Returns the first failure
  /// that stopped the drain, or null when everything landed (or nothing was
  /// queued). [silent] keeps automatic drains from flashing a message.
  Future<AppFailure?> flushPending({bool silent = false}) async {
    final auth = ref.read(authControllerProvider);
    final store = _store;
    if (auth is! AuthSignedIn || store == null) return null;
    final userId = auth.user.id;
    if (store.pending(userId).isEmpty) {
      ref.read(profileSyncProvider.notifier).setPending(0);
      return null;
    }

    final repo = ref.read(profileRepositoryProvider);
    AppFailure? failure;
    final delivered = await store.drain(userId, (write) async {
      try {
        await repo.patchProfile(userId: userId, values: write.values);
      } on AppFailure catch (f) {
        failure = f;
        rethrow;
      }
    });

    final sync = ref.read(profileSyncProvider.notifier);
    final left = store.pending(userId).length;
    sync.setPending(left);
    if (left == 0) {
      sync.markOnline();
      if (!silent && delivered > 0) sync.setNote('Everything is saved.');
    } else {
      sync.setNote(
        failure?.userMessage ??
            'Still offline — $left change${left == 1 ? '' : 's'} waiting.',
      );
    }
    return failure;
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
      final merged = updated.copyWith(
        statusText: statusText ?? updated.statusText,
        whereText: whereText ?? updated.whereText,
        labels: labels ?? updated.labels,
      );
      state = AsyncData(merged);
      _store?.cacheProfile(merged);
      return null;
    } on AppFailure catch (f) {
      return f;
    } catch (_) {
      return const ServerFailure();
    }
  }

  /// One privacy switch.
  ///
  /// Online: optimistic, then reconciled with the row the server returns.
  /// Offline: the switch stays where the person put it, the column write is
  /// queued, and [profileSyncProvider] says so — a tunnel must not silently
  /// un-flip a decision.
  Future<AppFailure?> setPrivacy(PrivacyField field, bool value) async {
    final auth = ref.read(authControllerProvider);
    final current = state.value;
    if (auth is! AuthSignedIn || current == null) {
      return const AuthFailure('Your session expired. Please log in again.');
    }

    final before = current;
    final optimistic = current.copyWith(
      privacy: current.privacy.withValue(field, value),
    );
    state = AsyncData(optimistic);
    _store?.cacheProfile(optimistic);

    try {
      final saved = await ref
          .read(profileRepositoryProvider)
          .updatePrivacy(userId: auth.user.id, field: field, value: value);
      final settled = before.copyWith(privacy: saved);
      state = AsyncData(settled);
      _store?.cacheProfile(settled);
      ref.read(profileSyncProvider.notifier).markOnline();
      return null;
    } on AppFailure catch (f) {
      // A retryable failure (offline, timeout, 5xx) must not undo a decision
      // someone made; a rejected one (403/validation) must.
      final retryable = f is NetworkFailure || f.isRetryable;
      if (retryable) {
        _enqueue(auth.user.id, <String, Object?>{field.column: value});
        return null;
      }
      state = AsyncData(before);
      _store?.cacheProfile(before);
      return f;
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
    final before = current;
    final optimistic = current.copyWith(labels: labels);
    state = AsyncData(optimistic);
    _store?.cacheProfile(optimistic);
    try {
      await ref
          .read(profileRepositoryProvider)
          .patchProfile(
            userId: auth.user.id,
            values: <String, Object?>{'labels': labels},
          );
      return null;
    } on AppFailure catch (f) {
      if (f is NetworkFailure) {
        _enqueue(auth.user.id, <String, Object?>{'labels': labels});
        return null;
      }
      state = AsyncData(before);
      _store?.cacheProfile(before);
      return f;
    }
  }

  /// Called by the photo studio once an upload (or a removal) has landed.
  void applyAvatar(String? avatarUrl) {
    final current = state.value;
    if (current == null) return;
    final updated = current.copyWith(
      avatarUrl: avatarUrl,
      clearAvatar: avatarUrl == null,
    );
    state = AsyncData(updated);
    _store?.cacheProfile(updated);
  }

  void _enqueue(String userId, Map<String, Object?> values) {
    final store = _store;
    if (store == null) return;
    store.enqueue(
      PendingWrite(
        id: _uuid.v4(),
        userId: userId,
        values: values,
        createdAt: DateTime.now(),
      ),
    );
    final sync = ref.read(profileSyncProvider.notifier);
    sync.setPending(store.pending(userId).length);
    sync.setNote(
      'Saved on this device — it will sync when you are back online.',
    );
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
