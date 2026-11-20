import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../domain/account_session.dart';
import '../domain/safety_action.dart';
import 'profile_controller.dart';

/// The owner's devices, for the account block of the Privacy lens.
final profileSessionsProvider =
    FutureProvider.autoDispose<List<AccountSession>>((ref) {
      return ref.watch(profileRepositoryProvider).sessions();
    });

/// Where a safety action is in its short life: idle → running → done/failed.
class SafetyState {
  const SafetyState({this.running, this.done, this.error});

  final SafetyAction? running;
  final SafetyAction? done;
  final String? error;

  bool get isBusy => running != null;
}

/// Runs the three things a visitor may do.
///
/// Every action here is a real write: `Clear` stamps
/// `conversation_members.cleared_at`, `Block` inserts into `public.blocks` (and
/// the database itself then refuses new messages both ways), `Report` files a
/// write-only row for the safety team. Nothing is a toast pretending to work.
class SafetyController extends Notifier<SafetyState> {
  @override
  SafetyState build() => const SafetyState();

  Future<AppFailure?> run(
    SafetyAction action, {
    required String targetUserId,
  }) async {
    state = SafetyState(running: action);
    final repo = ref.read(profileRepositoryProvider);
    try {
      switch (action) {
        case SafetyAction.clearChat:
          await repo.clearChatWith(targetUserId);
        case SafetyAction.block:
          await repo.blockUser(targetUserId);
        case SafetyAction.report:
          // The reason is chosen in the sheet; the default is the honest one
          // for a one-tap report.
          await repo.reportUser(
            targetUserId: targetUserId,
            reason: ReportReason.spam,
          );
      }
      state = SafetyState(done: action);
      return null;
    } on AppFailure catch (f) {
      state = SafetyState(error: f.userMessage);
      return f;
    } catch (_) {
      state = const SafetyState(error: 'That did not go through. Try again.');
      return const ServerFailure();
    }
  }

  Future<AppFailure?> report({
    required String targetUserId,
    required ReportReason reason,
  }) async {
    state = const SafetyState(running: SafetyAction.report);
    try {
      await ref
          .read(profileRepositoryProvider)
          .reportUser(targetUserId: targetUserId, reason: reason);
      state = const SafetyState(done: SafetyAction.report);
      return null;
    } on AppFailure catch (f) {
      state = SafetyState(error: f.userMessage);
      return f;
    } catch (_) {
      state = const SafetyState(error: 'That did not go through. Try again.');
      return const ServerFailure();
    }
  }

  /// True when this account has already blocked [targetUserId].
  Future<bool> isBlocked(String targetUserId) =>
      ref.read(profileRepositoryProvider).hasBlocked(targetUserId);

  Future<AppFailure?> unblock(String targetUserId) async {
    try {
      await ref.read(profileRepositoryProvider).unblockUser(targetUserId);
      state = const SafetyState();
      return null;
    } on AppFailure catch (f) {
      state = SafetyState(error: f.userMessage);
      return f;
    }
  }

  void idle() => state = const SafetyState();
}

final safetyControllerProvider =
    NotifierProvider<SafetyController, SafetyState>(SafetyController.new);

/// The owner's device list also needs "sign out everywhere else", which is an
/// auth operation, not a data one — but it belongs to the same block of UI.
final signOutOthersProvider = Provider<Future<AppFailure?> Function()>((ref) {
  return () async {
    try {
      await ref.read(profileRepositoryProvider).signOutOtherSessions();
      return null;
    } on AppFailure catch (f) {
      return f;
    } catch (_) {
      return const ServerFailure();
    }
  };
});
