import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../app/lifecycle.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../chat/data/chat_local_store.dart';
import '../../notifications/application/push_controller.dart';
import '../data/supabase_account_status_repository.dart';
import '../domain/account_status.dart';

final accountStatusRepositoryProvider = Provider<AccountStatusRepository>((
  ref,
) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure(
      'Supabase is not configured for this build.',
    );
  }
  return SupabaseAccountStatusRepository(Supabase.instance.client);
});

/// The hold, as the app holds it in memory.
///
/// Nothing here *decides* that an account is suspended — the server does that
/// (§25). This object exists so that the decision, once made, has one place to
/// land: every screen is replaced by the notice, the session is ended, realtime
/// is torn down and push stops. It is deliberately a single nullable value:
/// `null` means "no hold", and anything else is the case that is open.
class AccountLockController extends Notifier<AccountHold?> {
  /// True while the notice is signing in *only* to file an appeal. Without it
  /// the watchdog would end the very session the appeal needs.
  bool _appealSession = false;

  /// What the notice was last told, so a rebuild or a hot reload cannot turn a
  /// hold into a silent "no hold".
  AccountHold? get hold => state;

  @override
  AccountHold? build() => null;

  /// Called the moment the server says the account is restricted.
  ///
  /// Ends the session — tokens are dropped from the device, push is
  /// unregistered — and leaves the case on screen. Safe to call repeatedly:
  /// the first call wins, so a realtime event and a poll cannot both log out.
  Future<void> lock(AccountStatusInfo info) async {
    if (!info.isRestricted) return;
    if (state != null) return;
    final auth = ref.read(authControllerProvider);
    state = AccountHold(
      info: info,
      since: DateTime.now(),
      email: auth is AuthSignedIn ? auth.user.email : null,
    );
    if (_appealSession) return;
    await endSession();
  }

  /// The person chose to sign in again, only to ask a human to look. The hold
  /// stays; the logout is deferred until the appeal is filed.
  void beginAppealSession() => _appealSession = true;

  /// The appeal is filed (or abandoned): end the session for real and keep the
  /// notice exactly as it is.
  Future<void> endAppealSession() async {
    if (!_appealSession) return;
    _appealSession = false;
    await endSession();
  }

  /// "Sign in with a different account" — the one way out of the notice.
  void clear() {
    _appealSession = false;
    state = null;
  }

  Future<void> endSession() async {
    // Clear this account's scoped cache and queued sends before signing out.
    // Owner-less legacy entries are intentionally retained for safe recovery;
    // this is not a guarantee that all historical local data is erased.
    final auth = ref.read(authControllerProvider);
    final userId = auth is AuthSignedIn ? auth.user.id : null;
    try {
      if (userId != null) {
        await ChatLocalStore.instance?.forUser(userId).clear();
      }
    } catch (_) {
      // A cache that will not clear must not stop the logout.
    }
    bool sameAccount() {
      if (!ref.mounted || userId == null) return false;
      final current = ref.read(authControllerProvider);
      return current is AuthSignedIn && current.user.id == userId;
    }

    if (!sameAccount()) return;
    // Push first: it is the only call that needs the token row to still exist
    // (a suspended account's row is already deleted server-side, so this is
    // best-effort by design and must never block the sign-out).
    try {
      await ref.read(pushRegistrationProvider.notifier).handleSignOut();
    } catch (_) {
      // Sign-out is not allowed to fail because a token could not be retired.
    }
    if (!sameAccount()) return;
    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (_) {
      // The local session is cleared by the auth layer in a `finally`.
    }
  }
}

final accountLockProvider =
    NotifierProvider<AccountLockController, AccountHold?>(
      AccountLockController.new,
    );

/// How often a signed-in phone asks the server "am I still allowed?" when
/// Realtime is quiet. Twenty seconds is invisible to a person and closes the
/// window where a phone with a broken socket keeps working.
const accountStatusPollInterval = Duration(seconds: 20);

class AccountStatusController extends AsyncNotifier<AccountStatusInfo?> {
  StreamSubscription<AccountStatusInfo>? _changes;
  Timer? _poll;
  String? _userId;
  int _generation = 0;

  bool _isCurrent(String userId, int generation) {
    if (!ref.mounted || generation != _generation || _userId != userId) {
      return false;
    }
    final auth = ref.read(authControllerProvider);
    return auth is AuthSignedIn && auth.user.id == userId;
  }

  @override
  Future<AccountStatusInfo?> build() async {
    final auth = ref.watch(authControllerProvider);
    _stopWatching();

    if (auth is! AuthSignedIn) return null;
    final userId = auth.user.id;
    _userId = userId;
    final generation = _generation;
    final repo = ref.read(accountStatusRepositoryProvider);

    // A phone coming back from the background asks immediately: the hold may
    // have happened while the app was not allowed to talk to the network.
    ref.listen<AppLifecycleState>(appLifecycleProvider, (previous, next) {
      if (next == AppLifecycleState.resumed) unawaited(check());
    });

    ref.onDispose(_stopWatching);

    final info = await repo.fetchMine(userId);
    if (!_isCurrent(userId, generation)) return null;
    _startWatching(userId, generation, repo);
    _evaluate(info);
    return info;
  }

  /// One question, one answer, no UI churn: used by the poll, by lifecycle
  /// resume and by anything that just got a "you may not do that" back.
  Future<AccountStatusInfo?> check() async {
    final userId = _userId;
    if (userId == null) return null;
    final generation = _generation;
    try {
      final info = await ref
          .read(accountStatusRepositoryProvider)
          .fetchMine(userId);
      if (!_isCurrent(userId, generation)) return null;
      _evaluate(info);
      // Keep the cached value in step without flashing a loading state.
      if (!state.isLoading) state = AsyncData(info);
      return info;
    } catch (_) {
      // A failed check changes nothing: the last known truth stands.
      return _isCurrent(userId, generation) ? state.value : null;
    }
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    final generation = _generation;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final info = await ref
          .read(accountStatusRepositoryProvider)
          .fetchMine(userId);
      if (_isCurrent(userId, generation)) _evaluate(info);
      return info;
    });
    if (_isCurrent(userId, generation)) state = result;
  }

  void _evaluate(AccountStatusInfo info) {
    if (!info.isRestricted) return;
    unawaited(ref.read(accountLockProvider.notifier).lock(info));
  }

  void _startWatching(
    String userId,
    int generation,
    AccountStatusRepository repo,
  ) {
    _changes = repo.watch(userId).listen((info) {
      if (_isCurrent(userId, generation)) _evaluate(info);
    }, onError: (Object _) {});
    _poll = Timer.periodic(
      accountStatusPollInterval,
      (_) => unawaited(check()),
    );
  }

  void _stopWatching() {
    _generation++;
    _userId = null;
    unawaited(_changes?.cancel());
    _changes = null;
    _poll?.cancel();
    _poll = null;
  }
}

final accountStatusControllerProvider =
    AsyncNotifierProvider<AccountStatusController, AccountStatusInfo?>(
      AccountStatusController.new,
    );
