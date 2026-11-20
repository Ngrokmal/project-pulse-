import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/update_controller.dart';

/// Keeps the update prompt honest for the whole life of the app.
///
/// The splash screen asks once, before the app is entered. That is not enough:
/// if the user presses *Not now* — or leaves the app before Android finishes
/// installing — the old build is still running, and silently dropping the
/// prompt would leave them on it forever. This gate re-asks **every time the
/// app comes back to the foreground**, which is the behaviour the user asked
/// for: leave the app, come back, see the update page again if one exists.
///
/// It lives inside the signed-in shell on purpose — the prompt never interrupts
/// the welcome or auth screens, only the app itself.
class UpdateResumeGate extends ConsumerStatefulWidget {
  const UpdateResumeGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateResumeGate> createState() => _UpdateResumeGateState();
}

class _UpdateResumeGateState extends ConsumerState<UpdateResumeGate>
    with WidgetsBindingObserver {
  /// One re-check at a time: a phone that flaps between foreground and
  /// background must not stack release-channel calls.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Post-frame: the observer can fire while the tree is rebuilding.
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconsider());
    }
  }

  Future<void> _reconsider() async {
    if (!mounted || _busy) return;
    // The update page is already the foreground — re-entering it would reset
    // the download in progress.
    if (GoRouterState.of(context).uri.path == '/update') return;

    _busy = true;
    try {
      await ref.read(updateControllerProvider.notifier).reconsiderOnReturn();
    } finally {
      _busy = false;
    }
    if (!mounted) return;
    if (ref.read(updateControllerProvider).shouldPrompt) {
      context.go('/update');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
