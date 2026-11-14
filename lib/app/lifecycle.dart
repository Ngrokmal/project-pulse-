import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's lifecycle as a Riverpod value, so screens can react to it without
/// each one registering its own observer.
class AppLifecycleNotifier extends Notifier<AppLifecycleState> {
  AppLifecycleNotifier();

  AppLifecycleListener? _listener;

  @override
  AppLifecycleState build() {
    try {
      _listener = AppLifecycleListener(onStateChange: (next) => state = next);
    } on Object {
      // No binding (unit tests): stay resumed.
    }
    ref.onDispose(() => _listener?.dispose());
    return AppLifecycleState.resumed;
  }

  void set(AppLifecycleState state) => this.state = state;
}

final appLifecycleProvider =
    NotifierProvider<AppLifecycleNotifier, AppLifecycleState>(
      AppLifecycleNotifier.new,
    );

/// Throttles "refresh everything" work so a device that flickers between paused
/// and resumed does not hammer the network.
class ResumeRefresher {
  ResumeRefresher({this.minInterval = const Duration(seconds: 5)});

  final Duration minInterval;
  DateTime? _last;
  int runs = 0;

  /// Returns true when the callbacks actually ran.
  bool maybeRun(DateTime now, List<void Function()> callbacks) {
    final last = _last;
    if (last != null && now.difference(last) < minInterval) return false;
    _last = now;
    runs++;
    for (final cb in callbacks) {
      cb();
    }
    return true;
  }
}

final resumeRefresherProvider = Provider<ResumeRefresher>(
  (ref) => ResumeRefresher(),
);
