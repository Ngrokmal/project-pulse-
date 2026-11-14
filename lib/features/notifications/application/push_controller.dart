import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/auth_controller.dart';
import '../data/push_messaging_service.dart';
import '../data/supabase_push_token_repository.dart';
import '../domain/push_token.dart';
import '../domain/push_token_repository.dart';

final _log = AppLogger('push');

final pushMessagingServiceProvider = Provider<PushMessagingService>(
  (ref) => PushMessagingService(),
);

final pushTokenRepositoryProvider = Provider<PushTokenRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure('Supabase is not configured.');
  }
  return SupabasePushTokenRepository(Supabase.instance.client);
});

/// Notification permission as the OS reports it.
class PushPermissionController extends AsyncNotifier<PushPermission> {
  @override
  Future<PushPermission> build() =>
      ref.watch(pushMessagingServiceProvider).currentPermission();

  /// Shows the system prompt. Returns the resulting state so the UI can react
  /// immediately instead of waiting for a rebuild.
  Future<PushPermission> request() async {
    final service = ref.read(pushMessagingServiceProvider);
    final result = await service.requestPermission();
    state = AsyncData(result);
    // A grant unlocks delivery: sync the token right away.
    if (result.canDeliver) {
      await ref.read(pushRegistrationProvider.notifier).retry();
    }
    return result;
  }
}

final pushPermissionProvider =
    AsyncNotifierProvider<PushPermissionController, PushPermission>(
      PushPermissionController.new,
    );

/// Keeps `fcm_tokens` in sync with this install while an account is signed in,
/// and marks the token inactive on sign-out. Highest-priority subsystem (§31).
class PushRegistrationController extends AsyncNotifier<void> {
  String? _syncedToken;

  @override
  Future<void> build() async {
    final auth = ref.watch(authControllerProvider);
    final service = ref.watch(pushMessagingServiceProvider);

    if (auth is! AuthSignedIn) {
      _syncedToken = null;
      return;
    }

    final sub = service.tokenRefreshes.listen((token) async {
      _log.info('push_token_refreshed');
      await _sync(token);
    });
    ref.onDispose(sub.cancel);

    await _sync(await service.token());
    await service.allowForegroundPresentation();
  }

  Future<void> _sync(PushToken? token) async {
    if (token == null) {
      throw const ServerFailure(safeCode: 'push_token_unavailable');
    }
    final repo = ref.read(pushTokenRepositoryProvider);
    try {
      await repo.register(token);
    } on TokenOwnedByAnotherAccount {
      // The device was previously linked to a different account. Mint a fresh
      // token instead of leaving this account without push.
      _log.warning('push_token_rebinding');
      final fresh = await ref.read(pushMessagingServiceProvider).renewToken();
      if (fresh == null) {
        throw const ServerFailure(safeCode: 'push_token_unavailable');
      }
      await repo.register(fresh);
      _syncedToken = fresh.value;
      return;
    }
    _syncedToken = token.value;
    final active = await repo.activeTokenCount();
    _log.info('push_token_synced', data: {'activeTokens': active});
  }

  /// Called by the UI *before* signing out, while the session still exists.
  Future<void> handleSignOut() async {
    final value = _syncedToken;
    _syncedToken = null;
    if (value == null) return;
    try {
      await ref
          .read(pushTokenRepositoryProvider)
          .deactivate(PushToken(value: value));
    } catch (_) {
      // Sign-out must never be blocked by token bookkeeping.
    }
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _sync(await ref.read(pushMessagingServiceProvider).token());
    });
    if (state.hasError) _log.warning('push_sync_retry_failed');
  }

  /// The token currently registered for this install (null until synced).
  String? get syncedToken => _syncedToken;
}

final pushRegistrationProvider =
    AsyncNotifierProvider<PushRegistrationController, void>(
      PushRegistrationController.new,
    );
