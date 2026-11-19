import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/explore_motion.dart';
import '../domain/person.dart';

/// The one message Explore may show at a time, with an optional way back.
///
/// A toast is a *sentence about what just happened*: it carries the person, an
/// optional detail line, and at most one undo. It never carries an error stack —
/// failures are translated with [exploreFailureCopy] before they get here.
class ExploreToast {
  const ExploreToast({
    required this.message,
    this.detail,
    this.person,
    this.undoLabel = 'Undo',
    this.onUndo,
    this.tick = true,
  });

  final String message;
  final String? detail;
  final Person? person;
  final String undoLabel;
  final Future<void> Function()? onUndo;

  /// False for failures: a red dot reads better than a tick.
  final bool tick;

  bool get hasUndo => onUndo != null;
}

class ExploreFeedbackController extends Notifier<ExploreToast?> {
  Timer? _timer;

  @override
  ExploreToast? build() {
    ref.onDispose(() {
      _timer?.cancel();
      _timer = null;
    });
    return null;
  }

  void show(ExploreToast toast) {
    _timer?.cancel();
    state = toast;
    _timer = Timer(ExploreMotion.toastLife, () {
      if (state == toast) state = null;
    });
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }

  /// Runs the undo, then closes the toast even if the undo failed — the next
  /// toast will say what happened.
  Future<void> undo() async {
    final toast = state;
    if (toast == null) return;
    _timer?.cancel();
    _timer = null;
    state = null;
    final action = toast.onUndo;
    if (action != null) await action();
  }
}

final exploreFeedbackProvider =
    NotifierProvider<ExploreFeedbackController, ExploreToast?>(
      ExploreFeedbackController.new,
    );
