import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../domain/auth_repository.dart';

/// Supabase implementation of [AuthRepository].
/// Passwords are never persisted or logged anywhere in this app.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, {AppLogger? logger})
    : _log = logger ?? AppLogger('auth');

  final sb.SupabaseClient _client;
  final AppLogger _log;

  PulseUser _toUser(sb.User u) => PulseUser(
    id: u.id,
    email: u.email,
    displayName: (u.userMetadata?['display_name'] as String?)?.trim(),
  );

  @override
  Future<AuthOutcome?> restoreSession() async {
    final session = _client.auth.currentSession;
    if (session == null) return null;
    return AuthSuccess(user: _toUser(session.user));
  }

  @override
  Future<AuthSuccess> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = res.user;
      if (user == null) {
        throw const AuthFailure(
          'Sign in did not return a user.',
          kind: AuthFailureKind.unknown,
        );
      }
      _log.info('sign_in_ok', correlationId: user.id);
      return AuthSuccess(user: _toUser(user));
    } on sb.AuthException catch (e) {
      _log.warning('sign_in_failed', error: e.code);
      throw _mapAuthException(e);
    }
  }

  @override
  Future<AuthSuccess> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
      final user = res.user;
      if (user == null) {
        throw const AuthFailure(
          'Sign up did not return a user.',
          kind: AuthFailureKind.unknown,
        );
      }
      _log.info('sign_up_ok', correlationId: user.id);
      // Email confirmation may be required by project settings (§2 B).
      final needsConfirmation = res.session == null;
      return AuthSuccess(
        user: _toUser(user),
        needsEmailConfirmation: needsConfirmation,
      );
    } on sb.AuthException catch (e) {
      _log.warning('sign_up_failed', error: e.code);
      throw _mapAuthException(e);
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    _log.info('sign_out_ok');
  }

  @override
  Stream<PulseUser?> authStateChanges() => _client.auth.onAuthStateChange
      .map((s) => s.session?.user)
      .map((u) => u == null ? null : _toUser(u));

  AppFailure _mapAuthException(sb.AuthException e) {
    final code = e.code ?? '';
    final msg = (e.message).toLowerCase();
    if (code == 'invalid_credentials' ||
        msg.contains('invalid login credentials')) {
      return const AuthFailure(
        'Email or password is incorrect.',
        kind: AuthFailureKind.invalidCredentials,
      );
    }
    if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
      return const AuthFailure(
        'Confirm your email first — check your inbox.',
        kind: AuthFailureKind.emailNotConfirmed,
      );
    }
    if (code == 'user_already_exists' || msg.contains('already registered')) {
      return const AuthFailure(
        'An account already exists with this email.',
        kind: AuthFailureKind.emailInUse,
      );
    }
    if (code == 'weak_password' || msg.contains('password should be')) {
      return const AuthFailure(
        'That password is too weak. Use at least 8 characters.',
        kind: AuthFailureKind.weakPassword,
      );
    }
    if (code.contains('rate_limit') || msg.contains('rate limit')) {
      // Two very different situations share the 429 code:
      //  • over_email_send_rate_limit — the project's mailer is capped. Signing up
      //    is impossible until the cap resets or custom SMTP is configured, and no
      //    amount of "waiting a moment" helps. Say that, and point at sign-in.
      //  • anything else — a genuine throttling of attempts.
      final emailLimit =
          code.contains('email_send') || msg.contains('email rate limit');
      return AuthFailure(
        emailLimit
            ? 'Sign-up emails are rate limited on this project right now. '
                  'If you already have an account, log in instead — otherwise '
                  'try again later.'
            : 'Too many attempts. Please wait a moment and try again.',
        kind: emailLimit
            ? AuthFailureKind.emailRateLimited
            : AuthFailureKind.rateLimited,
      );
    }
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('host lookup')) {
      return NetworkFailure(detail: '${e.code ?? 'auth_error'}: ${e.message}');
    }
    return const AuthFailure(
      'Could not complete that request. Please try again.',
    );
  }
}
