import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/voice_playback_controller.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// The "clock hand" around a playing voice bubble, made unmistakable.
///
/// Three layers on one canvas, repainted from `[progress, orbit]` with no widget
/// rebuilds:
///
/// 1. **the progress arc** — starts at 12 o'clock, fills clockwise with the play
///    head, drawn 3.4 px wide in bright cyan with a dark rail behind it so it
///    reads on both the white and the purple bubble,
/// 2. **the traveller** — a cyan→violet segment orbiting the same rail every
///    2.1 s, blurred so it glows,
/// 3. **the halo** — a soft cyan ring outside the bubble that breathes with the
///    orbit, so "this is playing" is visible from across the room.
///
/// Everything is painted, not laid out: it costs one layer per frame.
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
      _orbit
        ..stop()
        ..value = 0;
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

  static const double _inset = 3;
  static const double _stroke = 3.4;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible || size.isEmpty) return;

    final rect = Rect.fromLTWH(
      -_inset,
      -_inset,
      size.width + _inset * 2,
      size.height + _inset * 2,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(radius + _inset),
    );
    final fraction = progress.value.fraction;

    // ---- the rail: a dark hairline, so the cyan has something to read against.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..isAntiAlias = true
        ..color = const Color(0x2EFFFFFF),
    );

    // ---- the progress arc, conic from 12 o'clock.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: 3 * math.pi / 2,
          colors: const [
            InboxPalette.cyan,
            Color(0xFF7FE4FF),
            InboxPalette.cyan,
            Color(0x00000000),
          ],
          stops: [
            0,
            (fraction * 0.5).clamp(0.0, 1.0),
            fraction.clamp(0.001, 0.999),
            fraction.clamp(0.001, 0.999),
          ],
        ).createShader(rect),
    );

    // ---- the outer halo: a breathing cyan glow on the outside of the bubble.
    final breath = 0.5 - 0.5 * math.cos(orbit.value * 2 * math.pi);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(3.5 + breath * 2.5),
        Radius.circular(radius + _inset + 3.5),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.5)
        ..color = InboxPalette.cyan.withValues(alpha: 0.28 + 0.22 * breath),
    );

    // ---- the traveller: one bright segment orbiting the rail.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(1.5),
        Radius.circular(radius + _inset + 1.5),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.4)
        ..shader = SweepGradient(
          colors: [
            InboxPalette.cyan.withValues(alpha: 0),
            InboxPalette.cyan,
            const Color(0xFF9B8AF5),
            InboxPalette.cyan.withValues(alpha: 0),
          ],
          stops: const [0, 0.13, 0.26, 0.40],
          transform: GradientRotation(orbit.value * 2 * math.pi - math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.visible != visible ||
      oldDelegate.radius != radius ||
      oldDelegate.progress != progress;
}
