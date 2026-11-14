import '../../../core/error/app_failure.dart';

/// Authenticated identity — the only user data the UI layer receives.
class PulseUser {
  const PulseUser({required this.id, required this.email, this.displayName});

  final String id;
  final String? email;
  final String? displayName;
}

sealed class AuthOutcome {
  const AuthOutcome();
}

/// Session is live and usable.
class AuthSuccess extends AuthOutcome {
  const AuthSuccess({required this.user, this.needsEmailConfirmation = false});
  final PulseUser user;
  final bool needsEmailConfirmation;
}

/// Operation failed with a typed, user-safe failure.
class AuthFailureOutcome extends AuthOutcome {
  const AuthFailureOutcome(this.failure);
  final AppFailure failure;
}

/// Abstraction so Supabase can be swapped/mocked and the UI stays testable
/// (master prompt §21: providers behind interfaces).
abstract class AuthRepository {
  /// Restores an existing session, or null when there is none.
  Future<AuthOutcome?> restoreSession();

  Future<AuthSuccess> signIn({required String email, required String password});

  Future<AuthSuccess> signUp({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> signOut();

  Stream<PulseUser?> authStateChanges();
}
