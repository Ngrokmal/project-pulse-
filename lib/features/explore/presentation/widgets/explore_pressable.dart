import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';

/// A press that answers with depth instead of ink.
///
/// The reference has no ripple on cards, pills or avatars — it sinks 2.5 px and
/// loses a little scale. One `AnimatedScale` per widget, no controllers.
class ExplorePressable extends StatefulWidget {
  const ExplorePressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final HitTestBehavior behavior;

  @override
  State<ExplorePressable> createState() => _ExplorePressableState();
}

class _ExplorePressableState extends State<ExplorePressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reducedMotion(context);
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: _enabled ? () => setState(() => _down = false) : null,
      child: AnimatedScale(
        scale: _down && !reduce ? widget.scale : 1,
        duration: reduce ? Duration.zero : ExploreMotion.press,
        curve: ExploreMotion.spring,
        child: widget.child,
      ),
    );
  }
}
