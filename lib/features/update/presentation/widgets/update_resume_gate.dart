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
/// It sits above the router, so it covers every screen the app can be on when
/// the user leaves — the tab shell, a chat, a call, settings — not just the
/// first tab. The welcome and auth screens are exempt: an update may interrupt
/// the app, never the way into an account.
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

  /// Launch is the splash screen's job. Only a return *after* the app was left
  /// counts as re-entering, so a cold start never checks twice.
  AppLifecycleState _last = AppLifecycleState.resumed;

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
    final wasAway =
        _last == AppLifecycleState.paused ||
        _last == AppLifecycleState.hidden ||
        _last == AppLifecycleState.detached;
    _last = state;
    if (state == AppLifecycleState.resumed && wasAway) {
      // Post-frame: the observer can fire while the tree is rebuilding.
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconsider());
    }
  }

  Future<void> _reconsider() async {
    if (!mounted || _busy) return;
    // Read the location from the delegate rather than from an inherited route
    // state: this gate sits *above* the router, where no route owns the context.
    final router = GoRouter.of(context);
    final path = router.routerDelegate.currentConfiguration.uri.path;
    // Already there: re-entering would reset a download in progress.
    if (path == '/update') return;
    // Not signed in yet: the way into the app is never interrupted.
    if (path == '/' || path == '/welcome' || path == '/auth') return;

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
