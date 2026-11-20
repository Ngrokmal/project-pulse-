import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'update_controller.dart';

/// How often the app asks the release channel, once it is *inside* the app.
///
/// The splash screen gets one short ask (two seconds). That is the right budget
/// for a launch and the wrong budget for a cold TLS handshake, so it times out
/// on a perfectly good connection more often than anyone would guess — and
/// before this class existed, a timed-out launch ask meant no update until the
/// app was backgrounded and brought back.
///
/// So the rule is: **while someone is in the app, keep asking.** Quickly at
/// first (a failed check retries in a few seconds, then backs off), calmly once
/// we know the build is current, and never twice at the same time.
class UpdateCadence {
  const UpdateCadence({
    this.first = const Duration(seconds: 3),
    this.max = const Duration(seconds: 30),
    this.calm = const Duration(minutes: 2),
  });

  /// The first retry after a failed ask. Doubles per consecutive failure.
  final Duration first;

  /// The ceiling the doubling stops at.
  final Duration max;

  /// The slow, steady beat once the installed build is the newest one.
  final Duration calm;

  /// The wait before the next ask, or `null` when there is nothing left to ask
  /// for — the update page is already the next thing the person will see.
  Duration? next(UpdatePhase phase, {required int failures}) {
    switch (phase) {
      case UpdatePhase.available:
      case UpdatePhase.downloading:
      case UpdatePhase.ready:
      case UpdatePhase.installing:
        return null;
      case UpdatePhase.upToDate:
        return calm;
      case UpdatePhase.checking:
        return first;
      case UpdatePhase.idle:
      case UpdatePhase.failed:
        var delay = first;
        for (var i = 0; i < failures; i++) {
          delay *= 2;
          if (delay >= max) return max;
        }
        return delay;
    }
  }
}

/// The heartbeat behind the update page.
///
/// Armed once for the life of the app (by [UpdateResumeGate]), it asks the
/// channel immediately — which is what makes an update appear within a couple of
/// seconds of reaching the home screen — and then keeps asking on
/// [UpdateCadence] until a build is offered, at which point it stops and lets the
/// page take over.
/// Reading providers, without caring whether it is a [Ref] or a
/// [ProviderContainer] — so the heartbeat is testable without a widget tree.
typedef UpdateRead = T Function<T>(ProviderListenable<T> provider);

class UpdateWatch {
  UpdateWatch(
    this._read, {
    this.cadence = const UpdateCadence(),
    this.budget = const Duration(seconds: 10),
  });

  final UpdateRead _read;
  final UpdateCadence cadence;

  /// How long one ask may take before it counts as failed. Longer than the
  /// launch budget on purpose: nothing is waiting on this one.
  final Duration budget;

  Timer? _timer;
  int _failures = 0;
  bool _active = false;
  bool _beating = false;

  /// True while the heartbeat is scheduled or in flight.
  bool get isWatching => _active;

  /// Number of consecutive failed asks — exposed for tests and diagnostics.
  int get failures => _failures;

  /// Starts the heartbeat. Safe to call repeatedly.
  void start() {
    if (_active) return;
    _active = true;
    unawaited(_beat());
  }

  /// Stops it, cancelling any pending ask.
  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Asks now, out of turn (a resume, a retry button). Keeps the rhythm.
  Future<void> poke() async {
    if (!_active) {
      start();
      return;
    }
    _timer?.cancel();
    _timer = null;
    await _beat();
  }

  Future<void> _beat() async {
    if (!_active || _beating) return;
    _beating = true;
    try {
      final notifier = _read(updateControllerProvider.notifier);
      final before = _read(updateControllerProvider);
      // A launch ask may still be in flight; `check` joins it instead of
      // opening a second connection.
      if (!before.isWorking) {
        await notifier.check(budget: budget);
      }
      if (!_active) return;

      final after = _read(updateControllerProvider);
      // The cadence is asked with the failures *so far*, so the first retry is
      // `first` and only the ones after it double.
      final delay = cadence.next(after.phase, failures: _failures);
      _failures = after.phase == UpdatePhase.failed ? _failures + 1 : 0;
      if (delay == null) {
        // An update is on offer — the page is where the person goes next, so
        // the heartbeat has done its job.
        stop();
        return;
      }
      _timer = Timer(delay, _beat);
    } finally {
      _beating = false;
    }
  }
}

final updateCadenceProvider = Provider<UpdateCadence>(
  (ref) => const UpdateCadence(),
);

final updateWatchProvider = Provider<UpdateWatch>((ref) {
  final watch = UpdateWatch(ref.read, cadence: ref.read(updateCadenceProvider));
  ref.onDispose(watch.stop);
  return watch;
});
