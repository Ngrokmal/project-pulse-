import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/update_controller.dart';
import '../../application/update_watch.dart';

/// Keeps the update prompt honest for the whole life of the app.
///
/// Two mechanisms, because one was not enough:
///
///  • **the heartbeat** ([UpdateWatch]) asks the release channel the moment the
///    app is entered — no waiting for a resume, no waiting for a tap. If that
///    ask fails it asks again in a few seconds, backing off, so a launch whose
///    two-second splash check timed out still offers the update a moment later
///    on the home screen. It keeps a slow beat while the build is current, so a
///    release published while the app is open arrives on its own.
///  • **the listener** below turns a finished ask into the update page from
///    wherever the person is standing, which is what makes the update *appear*
///    rather than merely be known.
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

  /// The router's notifier, so "the person is now inside the app" is an event
  /// this gate hears rather than a fact it polls for.
  Listenable? _routes;

  /// Held, not looked up: `dispose` may not touch `ref`, and stopping the
  /// heartbeat is exactly a `dispose` job.
  UpdateWatch? _watch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Armed on the frame after the gate mounts, so the first ask is already in
    // flight while the splash is still fading out — the answer is usually back
    // before the home screen has finished its first paint.
    _watch = ref.read<UpdateWatch>(updateWatchProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _watch?.start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final delegate = GoRouter.of(context).routerDelegate;
    if (!identical(delegate, _routes)) {
      _routes?.removeListener(_onRouteChanged);
      _routes = delegate..addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    _routes?.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    _watch?.stop();
    super.dispose();
  }

  /// Every route change: if it landed *inside* the app, the heartbeat is put
  /// back to work and an update that is already on offer is shown immediately.
  ///
  /// This is the case the splash screen cannot cover — a cold start that timed
  /// out, an update that landed while the sign-in screens were up, a *Later*
  /// pressed earlier in the session.
  void _onRouteChanged() {
    if (!mounted) return;
    final path = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    // Onboarding is never interrupted, and the update page is already the
    // answer — re-arming there would only re-flash its checking state.
    if (path == '/' || path == '/welcome' || path == '/auth') return;
    if (path == '/update') {
      _watch?.stop();
      return;
    }
    final watch = _watch ?? ref.read<UpdateWatch>(updateWatchProvider);
    if (!watch.isWatching) watch.start();
    if (ref.read(updateControllerProvider).shouldPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showIfOffered());
    }
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
      // The heartbeat may have stopped itself after offering a build the person
      // then dismissed; coming back is exactly when it should start again.
      (_watch ?? ref.read<UpdateWatch>(updateWatchProvider)).start();
    } finally {
      _busy = false;
    }
    if (!mounted) return;
    if (ref.read(updateControllerProvider).shouldPrompt) {
      context.go('/update');
    }
  }

  /// The instant an ask lands on a newer build, go to the page — wherever the
  /// person happens to be, as long as it is not the way into an account.
  void _showIfOffered() {
    if (!mounted) return;
    if (!ref.read(updateControllerProvider).shouldPrompt) return;
    final path = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    if (path == '/update' ||
        path == '/' ||
        path == '/welcome' ||
        path == '/auth') {
      return;
    }
    context.go('/update');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateState>(updateControllerProvider, (previous, next) {
      if (!next.shouldPrompt) return;
      if (previous?.shouldPrompt == true) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showIfOffered());
    });
    return widget.child;
  }
}
