import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';

/// The avatar's ring, ported from the v4 card: an **aperture**, not an outline.
///
/// Four parts, each doing one job:
///   • a hairline socket       — gives the eye a circle to sit in (static)
///   • a comet                 — a bright head with a long tail, 5.4s per lap
///   • a spark                 — one bead of light on the comet's head
///   • a breathing bloom       — a slow halo behind the glass, 7.4s per breath
///
/// The glass itself carries no border: depth comes from a shadow, so the ring
/// reads as a bezel around a lens rather than a stroke around a sticker.
class OrbitRing extends StatefulWidget {
  const OrbitRing({
    super.key,
    required this.face,
    this.faceSize = 118,
    this.spark = true,
    this.gap = 2.5,
    this.onTap,
    this.badge,
    this.overlay,
  });

  /// The avatar itself (image or initials).
  final Widget face;

  /// Diameter of the glass, in logical pixels.
  final double faceSize;

  /// The travelling bead. Off for the small studio preview.
  final bool spark;

  /// Distance between the glass and the ring, in logical pixels.
  final double gap;

  final VoidCallback? onTap;

  /// The camera bead (owner) — sits at the glass's lower right.
  final Widget? badge;

  /// The presence ping (visitor) — sits opposite the badge.
  final Widget? overlay;

  /// Full footprint, so callers can reserve space exactly.
  double get footprint => faceSize + 2 * (gap + 12);

  @override
  State<OrbitRing> createState() => _OrbitRingState();
}

class _OrbitRingState extends State<OrbitRing> with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5400),
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _sweep
        ..stop()
        ..value = 0.12;
      _breath
        ..stop()
        ..value = 0.5;
    } else {
      if (!_sweep.isAnimating) _sweep.repeat();
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The comet rides a hair outside the glass: a gap wide enough to read as
    // a bezel, narrow enough that it never becomes a dark disc around the face.
    final ringDiameter = widget.faceSize + widget.gap * 2 + 3;
    final box = widget.faceSize + 2 * (widget.gap + 12);

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // breathing bloom
            AnimatedBuilder(
              animation: _breath,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_breath.value);
                return IgnorePointer(
                  child: Transform.scale(
                    scale: 0.94 + 0.12 * t,
                    child: Container(
                      // Proportional, so a 40 px portrait gets a halo the size
                      // of a portrait and not one that has to be clipped.
                      width: widget.faceSize * 1.5,
                      height: widget.faceSize * 1.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.brand400.withValues(
                              alpha: 0.20 + 0.10 * t,
                            ),
                            AppColors.brand600.withValues(alpha: 0.10),
                            AppColors.blue500.withValues(alpha: 0.0),
                          ],
                          stops: const [0, 0.52, 0.78],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // the socket + comet + spark, one paint pass
            AnimatedBuilder(
              animation: _sweep,
              builder: (context, _) => CustomPaint(
                size: Size.square(box),
                painter: _OrbitPainter(
                  diameter: box,
                  ringDiameter: ringDiameter,
                  phase: _sweep.value,
                  spark: widget.spark,
                ),
              ),
            ),
            widget.face,
            if (widget.overlay != null)
              Positioned(
                right: widget.gap + 6,
                bottom: widget.gap + 14,
                child: widget.overlay!,
              ),
            if (widget.badge != null)
              Positioned(
                right: widget.gap + 2,
                bottom: widget.gap + 2,
                child: widget.badge!,
              ),
          ],
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.diameter,
    required this.ringDiameter,
    required this.phase,
    required this.spark,
  });

  final double diameter;
  final double ringDiameter;

  /// 0…1 — one lap of the comet.
  final double phase;
  final bool spark;

  static const double _headDegrees = 122;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = ringDiameter / 2;
    final angle = phase * 2 * math.pi;

    // 1. the socket: a circle you feel more than see
    canvas.drawCircle(
      center,
      radius + 4.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withValues(alpha: 0.20),
    );

    // 2. the comet: a sweep shader that is transparent for most of the lap and
    //    bright at the head, rotated by the controller
    final sweep = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: 0),
        AppColors.brand300.withValues(alpha: 0.06),
        AppColors.brand200.withValues(alpha: 0.18),
        const Color(0xFFEDE6FF).withValues(alpha: 0.42),
        Colors.white.withValues(alpha: 0.85),
        Colors.white,
        Colors.white.withValues(alpha: 0.30),
        Colors.white.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.10, 0.20, 0.27, 0.32, 0.345, 0.36, 0.375, 0.40],
      transform: GradientRotation(angle),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..shader = sweep.createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );

    // 3. the spark: one bead of light on the head, with a soft halo
    if (!spark) return;
    final sparkAngle = angle - math.pi / 2 + _headDegrees * math.pi / 180;
    final head =
        center + Offset(math.cos(sparkAngle), math.sin(sparkAngle)) * radius;

    canvas.drawCircle(
      head,
      9,
      Paint()
        ..color = AppColors.brand200.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      head,
      4.2,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.drawCircle(head, 2.1, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.phase != phase ||
      old.ringDiameter != ringDiameter ||
      old.spark != spark;
}
