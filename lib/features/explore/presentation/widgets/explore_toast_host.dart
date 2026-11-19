import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/explore_feedback_controller.dart';
import 'explore_toast_view.dart';

/// Where a toast lives.
///
/// Explore can show a message from the tab *and* from the search sheet, and the
/// sheet is a dialog route on top of the tab — so the toast is hosted by both,
/// reading the same provider. Only the one that is actually visible matters.
class ExploreToastHost extends ConsumerWidget {
  const ExploreToastHost({super.key, this.bottomInset = 96});

  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(exploreFeedbackProvider);
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomInset,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ExploreToastView(
          toast: toast,
          onUndo: () => ref.read(exploreFeedbackProvider.notifier).undo(),
        ),
      ),
    );
  }
}
