import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';

/// Swipe to decide: pull right to accept, left to decline.
///
/// • the underlay fades in as a share of the commit distance, so the card tells
///   you what will happen before you let go;
/// • the card tilts one degree per 26 px, and rubber-bands past 190 px so it can
///   never fly out of its own row;
/// • under the commit distance it springs home on the overshoot curve.
///
/// Only this widget rebuilds while a finger is down — the card itself is passed
/// in as `child` and is never rebuilt mid-drag.
class SwipeDecisionCard extends StatefulWidget {
  const SwipeDecisionCard({
    super.key,
    required this.child,
    required this.onAccept,
    required this.onDecline,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool enabled;

  @override
  State<SwipeDecisionCard> createState() => _SwipeDecisionCardState();
}

class _SwipeDecisionCardState extends State<SwipeDecisionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: ExploreMotion.swipeSettle,
  );

  double _dx = 0;
  double _from = 0;
  double _to = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      final curved = ExploreMotion.easeOut.transform(_settle.value);
      setState(() => _dx = _from + (_to - _from) * curved);
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails _) {
    if (!widget.enabled) return;
    _settle.stop();
    _dragging = true;
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!widget.enabled || !_dragging) return;
    var next = _dx + details.delta.dx;
    final limit = ExploreMotion.swipeResistAfter;
    if (next.abs() > limit) {
      // Past the row's width the card should resist, not detach.
      final overshoot = next.abs() - limit;
      next = next.sign * (limit + math.pow(overshoot, 0.86) * 0.6);
    }
    setState(() => _dx = next);
  }

  void _onEnd(DragEndDetails _) {
    if (!_dragging) return;
    _dragging = false;

    if (!widget.enabled) {
      _animateTo(0);
      return;
    }

    if (_dx.abs() >= ExploreMotion.swipeCommit) {
      final accepted = _dx > 0;
      // Let the card finish its exit, then hand the decision over.
      _animateTo(
        accepted ? 420 : -420,
        onDone: () {
          if (!mounted) return;
          setState(() => _dx = 0);
          accepted ? widget.onAccept() : widget.onDecline();
        },
      );
      return;
    }
    _animateTo(0);
  }

  void _animateTo(double target, {VoidCallback? onDone}) {
    _from = _dx;
    _to = target;
    _settle
      ..stop()
      ..duration = target == 0
          ? ExploreMotion.swipeRelease
          : ExploreMotion.swipeSettle;
    // A cancelled animation never completes this future, which is exactly right:
    // only a finished exit may hand the decision over.
    _settle.forward(from: 0).then((_) {
      if (mounted && onDone != null) onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reducedMotion(context);
    final share = (_dx.abs() / ExploreMotion.swipeCommit).clamp(0.0, 1.0);
    final tilt = reduce ? 0.0 : _dx / ExploreMotion.swipeTiltPerPixel;

    return ClipRRect(
      borderRadius: BorderRadius.circular(ExploreMotion.cardRadius),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: _DecisionUnderlay(share: share, accepted: _dx >= 0),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _onStart,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            onHorizontalDragCancel: () => _animateTo(0),
            child: Transform.translate(
              offset: Offset(_dx, 0),
              child: Transform.rotate(
                angle: tilt * math.pi / 180,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DecisionUnderlay extends StatelessWidget {
  const _DecisionUnderlay({required this.share, required this.accepted});

  final double share;
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final visible = share <= 0.02 ? 0.0 : (0.35 + share * 0.65);
    final color = accepted ? const Color(0xFF17C653) : const Color(0xFFEF3E4A);

    return Opacity(
      opacity: visible,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: accepted ? Alignment.centerLeft : Alignment.centerRight,
            end: accepted ? Alignment.centerRight : Alignment.centerLeft,
            colors: <Color>[color, color.withValues(alpha: 0.72)],
          ),
        ),
        alignment: accepted ? Alignment.centerLeft : Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!accepted) ...[
              Text('DECLINE', style: _labelStyle),
              const SizedBox(width: 8),
              const Icon(Icons.close_rounded, color: Colors.white, size: 18),
            ] else ...[
              const Icon(Icons.check_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('ACCEPT', style: _labelStyle),
            ],
          ],
        ),
      ),
    );
  }

  static const TextStyle _labelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.6,
    color: Colors.white,
    height: 1,
  );
}
