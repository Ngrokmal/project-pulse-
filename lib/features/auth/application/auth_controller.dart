import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';

/// Injected so tests can override with a fake (no Supabase in unit tests).
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure(
      'SUPABASE_URL / SUPABASE_ANON_KEY missing at build time.',
    );
  }
  return SupabaseAuthRepository(Supabase.instance.client);
});

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.user);
  final PulseUser user;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnknown();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Restores a session on startup. Never throws to the UI.
  Future<void> restore() async {
    try {
      final outcome = await _repo.restoreSession();
      state = switch (outcome) {
        AuthSuccess(user: final u) => AuthSignedIn(u),
        _ => const AuthSignedOut(),
      };
    } catch (_) {
      state = const AuthSignedOut();
    }
  }

  /// Returns null on success, or a typed failure for the UI to display.
  Future<AppFailure?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _repo.signIn(email: email.trim(), password: password);
      state = AuthSignedIn(res.user);
      return null;
    } on AppFailure catch (f) {
      return f;
    } catch (_) {
      return const ServerFailure();
    }
  }

  Future<AuthSuccess?> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final res = await _repo.signUp(
      displayName: displayName.trim(),
      email: email.trim(),
      password: password,
    );
    if (!res.needsEmailConfirmation) {
      state = AuthSignedIn(res.user);
    }
    return res;
  }

  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } finally {
      state = const AuthSignedOut();
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
