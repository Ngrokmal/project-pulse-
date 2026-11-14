import '../../../core/error/app_failure.dart';
import 'push_token.dart';

/// Raised when the token belongs to an fcm_tokens row that RLS will not let this
/// account touch (the device was previously linked to another account). The
/// caller must discard the token (`FirebaseMessaging.deleteToken()`) and retry
/// with a fresh one rather than silently failing.
class TokenOwnedByAnotherAccount implements Exception {
  const TokenOwnedByAnotherAccount();
}

abstract interface class PushTokenRepository {
  /// Registers [token] for the signed-in user, reactivating it if this account
  /// already owned it. Throws [TokenOwnedByAnotherAccount] when the row exists
  /// under someone else's account.
  Future<void> register(PushToken token);

  /// Marks this device's token inactive (called on sign-out so a shared device
  /// stops receiving the previous account's notifications).
  Future<void> deactivate(PushToken token);

  /// Number of active tokens the signed-in user has. Used to prove the sync
  /// actually landed instead of assuming it did.
  Future<int> activeTokenCount();
}

/// Convenience: turn any repository failure into the typed failure the UI shows.
AppFailure asFailure(Object error) => switch (error) {
  AppFailure() => error,
  TokenOwnedByAnotherAccount() => const ServerFailure(
    safeCode: 'push_token_foreign',
  ),
  _ => const ServerFailure(safeCode: 'push_sync_failed'),
};
