import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';

/// One shimmer for every pill: a soft white band crossing the fill on a 2.6 s
/// loop. Wrapped in a `RepaintBoundary` so it never dirties its parent.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reducedMotion(context)) return widget.child;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (rect) {
              final dx = (_controller.value * 2.4 - 1.2) * rect.width;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const <Color>[
                  Color(0x00FFFFFF),
                  Color(0xE6FFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: const <double>[0.35, 0.5, 0.65],
                transform: _SlideGradient(dx),
              ).createShader(rect);
            },
            child: child,
          );
        },
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);
  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// **Requested** — the state that means "waiting", not "done".
class RequestedPill extends StatelessWidget {
  const RequestedPill({
    super.key,
    required this.onTap,
    this.cancellable = true,
    this.label = 'Requested',
  });

  final VoidCallback? onTap;
  final bool cancellable;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: cancellable,
      label: cancellable ? '$label — tap to cancel' : label,
      child: GestureDetector(
        onTap: cancellable ? onTap : null,
        child: Container(
          height: 33,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFF5F1FF), Color(0xFFEDE7FF)],
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: ExplorePalette.requestedBorder, width: 1),
          ),
          child: _Shimmer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size(12, 12),
                  painter: _TickPainter(color: ExplorePalette.requestedInk),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: ExplorePalette.requestedInk,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.16, size.height * 0.55)
      ..lineTo(size.width * 0.42, size.height * 0.8)
      ..lineTo(size.width * 0.86, size.height * 0.24);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => oldDelegate.color != color;
}

/// The warm **PENDING** pill used on a sent request.
class PendingPill extends StatelessWidget {
  const PendingPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFF6E5), Color(0xFFFFEFD2)],
        ),
        borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
      ),
      child: _Shimmer(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: ExplorePalette.pendingInk,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'PENDING',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
                color: ExplorePalette.pendingInk,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny uppercase badge; `null` when the action button already says it.
class RelationBadge extends StatelessWidget {
  const RelationBadge({
    super.key,
    required this.label,
    required this.tint,
    required this.ink,
  });

  final String label;
  final Color tint;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: ink,
          height: 1,
        ),
      ),
    );
  }
}

/// **NEW** — shown for a friendship that was made a moment ago, then fades.
class NewChip extends StatefulWidget {
  const NewChip({super.key});

  @override
  State<NewChip> createState() => _NewChipState();
}

class _NewChipState extends State<NewChip> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ExploreMotion.newChipFade,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(ExploreMotion.newChipHold, () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        height: 17,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: ExplorePalette.badgeFriendBg,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: const Text(
          'NEW',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            color: ExplorePalette.badgeFriendInk,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// The number inside a segment: it pops when it changes, and never shows `0`.
class SegmentCount extends StatelessWidget {
  const SegmentCount({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    if (value <= 0) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: ExploreMotion.press,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Container(
        key: ValueKey<int>(value),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: ExplorePalette.brand100,
          borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
        ),
        child: Text(
          '$value',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: ExplorePalette.brand700,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
