import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/voice_playback_controller.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// The "clock hand" around a playing voice bubble.
///
/// Two layers, exactly like the reference:
///
/// * a **progress arc** starting at 12 o'clock that fills clockwise with the
///   play head — this is the needle you read progress from,
/// * a **traveller**: a bright cyan→violet segment orbiting the same rail every
///   2.1 s, so the bubble keeps moving even between progress ticks.
///
/// Both are painted on one canvas, repainted from `[progress, orbit]`; no widget
/// rebuilds happen per frame.
class PlaybackRing extends StatefulWidget {
  const PlaybackRing({
    super.key,
    required this.progress,
    required this.playing,
    required this.radius,
  });

  final ValueListenable<PlaybackProgress> progress;
  final bool playing;
  final double radius;

  @override
  State<PlaybackRing> createState() => _PlaybackRingState();
}

class _PlaybackRingState extends State<PlaybackRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: InboxMotion.orbit,
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _orbit.repeat();
  }

  @override
  void didUpdateWidget(PlaybackRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_orbit.isAnimating) {
      _orbit.repeat();
    } else if (!widget.playing && _orbit.isAnimating) {
      _orbit.stop();
      _orbit.value = 0;
    }
  }

  @override
  void dispose() {
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _RingPainter(
          progress: widget.progress,
          orbit: _orbit,
          radius: widget.radius,
          visible: widget.playing,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.orbit,
    required this.radius,
    required this.visible,
  }) : super(repaint: Listenable.merge([progress, orbit]));

  final ValueListenable<PlaybackProgress> progress;
  final AnimationController orbit;
  final double radius;
  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible || size.isEmpty) return;
    const inset = 2.5;
    final rect = Rect.fromLTWH(
      -inset,
      -inset,
      size.width + inset * 2,
      size.height + inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius + inset),
    );
    final shaderRect = rect;

    // ---- progress arc: conic from -90°, cyan solid then a 18 % white rail.
    final fraction = progress.value.fraction;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..isAntiAlias = true
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: const [
          InboxPalette.cyan,
          InboxPalette.cyan,
          Color(0x2EFFFFFF),
          Color(0x2EFFFFFF),
        ],
        stops: [
          0,
          fraction.clamp(0.001, 0.999),
          fraction.clamp(0.001, 0.999),
          1,
        ],
        transform: const GradientRotation(0),
      ).createShader(shaderRect);
    canvas.drawRRect(rrect, progressPaint);

    // ---- the traveller: one segment orbiting the rail.
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..isAntiAlias = true
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2)
      ..shader = SweepGradient(
        colors: [
          InboxPalette.cyan.withValues(alpha: 0),
          InboxPalette.cyan.withValues(alpha: 0.95),
          const Color(0xFF9B8AF5).withValues(alpha: 0.95),
          InboxPalette.cyan.withValues(alpha: 0),
        ],
        stops: const [0, 0.14, 0.27, 0.42],
        transform: GradientRotation(orbit.value * 2 * math.pi - math.pi / 2),
      ).createShader(shaderRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(1.5),
        Radius.circular(radius + inset + 1.5),
      ),
      orbitPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.visible != visible ||
      oldDelegate.radius != radius ||
      oldDelegate.progress != progress;
}
