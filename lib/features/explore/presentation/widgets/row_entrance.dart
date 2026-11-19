import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';

/// The reference's entrance: rise 14 px, scale .97 → 1, 520 ms on the spring.
///
/// Each row owns one short-lived controller rather than a list-wide ticker, so a
/// single row arriving (a new request, a new friend) never rebuilds its siblings.
class RowEntrance extends StatefulWidget {
  const RowEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;

  /// Staggers a freshly built list: index × [ExploreMotion.rowStagger].
  final Duration delay;

  @override
  State<RowEntrance> createState() => _RowEntranceState();
}

class _RowEntranceState extends State<RowEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ExploreMotion.rowEnter,
    );
    _curve = CurvedAnimation(parent: _controller, curve: ExploreMotion.spring);
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reducedMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, ExploreMotion.enterRise * (1 - t)),
            child: Transform.scale(
              scale:
                  ExploreMotion.enterScale + (1 - ExploreMotion.enterScale) * t,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
