import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/widgets/state_views.dart';
import '../application/account_status_controller.dart';
import 'account_on_hold_screen.dart';

/// Keeps the signed-in area behind the account's server state (§25).
///
/// The heavy lifting is not here: the watchdog (see
/// `accountStatusControllerProvider`) watches the server row and the router
/// redirects every location to the notice. This gate is the last line — the one
/// that guarantees a held account sees the notice even if a route was pushed
/// over the top of the shell.
class AccountGate extends ConsumerWidget {
  const AccountGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hold = ref.watch(accountLockProvider);
    if (hold != null) return const AccountOnHoldScreen();

    final status = ref.watch(accountStatusControllerProvider);
    return status.when(
      loading: () =>
          const Scaffold(body: PulseLoading(message: 'Checking your account')),
      error: (error, _) => Scaffold(
        body: PulseErrorState(
          failure: error is AppFailure
              ? error
              : const ServerFailure(safeCode: 'status_unavailable'),
          onRetry: () =>
              ref.read(accountStatusControllerProvider.notifier).refresh(),
        ),
      ),
      data: (info) {
        // `info` being restricted means the watchdog has already locked the
        // app; showing the notice a frame early is the honest thing to do.
        if (info != null && info.isRestricted) {
          return const AccountOnHoldScreen();
        }
        return child;
      },
    );
  }
}
