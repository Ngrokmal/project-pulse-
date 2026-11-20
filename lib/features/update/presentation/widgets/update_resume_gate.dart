import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// ### Why the router is passed in, not looked up
///
/// This widget sits in `MaterialApp.router`'s `builder` — *above* the
/// `InheritedGoRouter` that the router's delegate provides, which is the whole
/// point: it has to cover every screen. `GoRouter.of(context)` therefore finds
/// nothing there and throws, and because it used to be called from
/// `didChangeDependencies` that throw happened during the very first build and
/// took the entire app down to a white screen.
///
/// So the app hands in exactly the two things this needs — where we are, and how
/// to open the update page — and this widget never touches the router's
/// inherited scope.
class UpdateResumeGate extends ConsumerStatefulWidget {
  const UpdateResumeGate({
    super.key,
    required this.child,
    required this.routes,
    required this.location,
    required this.openUpdate,
  });

  final Widget child;

  /// The router's own notifier ([GoRouter.routerDelegate]), so "the person has
  /// just arrived somewhere inside the app" is an event this gate hears.
  final Listenable routes;

  /// Current route path, e.g. `/app`. Read from the delegate, never inferred.
  final String Function() location;

  /// Opens the update page.
  final VoidCallback openUpdate;

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

  /// Held, not looked up: `dispose` may not touch `ref`, and stopping the
  /// heartbeat is exactly a `dispose` job.
  UpdateWatch? _watch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch = ref.read<UpdateWatch>(updateWatchProvider);
    widget.routes.addListener(_onRouteChanged);
    // Armed on the frame after the gate mounts, so the first ask is already in
    // flight while the splash is still fading out — the answer is usually back
    // before the home screen has finished its first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _watch?.start();
    });
  }

  @override
  void didUpdateWidget(UpdateResumeGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.routes, widget.routes)) {
      oldWidget.routes.removeListener(_onRouteChanged);
      widget.routes.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    widget.routes.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    _watch?.stop();
    super.dispose();
  }

  /// Onboarding is never interrupted, and the update page is already the
  /// answer.
  static bool _isOnboarding(String path) =>
      path == '/' || path == '/welcome' || path == '/auth';

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

  /// Every route change: if it landed *inside* the app, the heartbeat is put
  /// back to work and an update that is already on offer is shown immediately.
  ///
  /// This is the case the splash screen cannot cover — a cold start that timed
  /// out, an update that landed while the sign-in screens were up, a *Later*
  /// pressed earlier in the session.
  void _onRouteChanged() {
    if (!mounted) return;
    // The delegate notifies *while it is building* the new route, and starting
    // the heartbeat writes its `checking` phase — which Riverpod refuses
    // mid-build. One frame later is soon enough by any measure.
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterRouteChange());
  }

  void _afterRouteChange() {
    if (!mounted) return;
    final path = widget.location();
    if (_isOnboarding(path)) return;
    if (path == '/update') {
      // Already there: re-arming would only re-flash its checking state.
      _watch?.stop();
      return;
    }
    final watch = _watch ?? ref.read<UpdateWatch>(updateWatchProvider);
    if (!watch.isWatching) watch.start();
    if (ref.read(updateControllerProvider).shouldPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showIfOffered());
    }
  }

  Future<void> _reconsider() async {
    if (!mounted || _busy) return;
    final path = widget.location();
    // Already there: re-entering would reset a download in progress.
    if (path == '/update') return;
    // Not signed in yet: the way into the app is never interrupted.
    if (_isOnboarding(path)) return;

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
    _showIfOffered();
  }

  /// The instant an ask lands on a newer build, go to the page — wherever the
  /// person happens to be, as long as it is not the way into an account.
  void _showIfOffered() {
    if (!mounted) return;
    if (!ref.read(updateControllerProvider).shouldPrompt) return;
    final path = widget.location();
    if (path == '/update' || _isOnboarding(path)) return;
    widget.openUpdate();
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
