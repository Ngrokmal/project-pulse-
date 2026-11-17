import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../application/inbox_audio_level.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// The 22 live bars inside the recorder pill.
///
/// Height comes from `4 + level*21*shape + 1.6*wobble`, clamped to 3..26 — the
/// reference formula, fed by the same level as everything else and painted
/// through `repaint: level` so no widget rebuilds per frame.
class RecorderWave extends StatelessWidget {
  const RecorderWave({
    super.key,
    required this.level,
    required this.paused,
    this.bars = InboxMotion.waveformBars,
  });

  final InboxAudioLevel level;
  final bool paused;

  /// 22 bars when there is room; fewer, thicker bars when the hint needs space.
  final int bars;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(double.infinity, 26),
        painter: _RecorderWavePainter(level: level, paused: paused, bars: bars),
      ),
    );
  }
}

class _RecorderWavePainter extends CustomPainter {
  _RecorderWavePainter({
    required this.level,
    required this.paused,
    required this.bars,
  }) : super(repaint: level);

  final InboxAudioLevel level;
  final bool paused;
  final int bars;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final lvl = paused ? 0.0 : level.value;
    final count = bars.clamp(4, InboxMotion.waveformBars);
    final gap = count >= 16 ? 2.0 : 2.5;
    final barWidth = ((size.width - gap * (count - 1)) / count).clamp(1.8, 6.0);
    final spacing = count > 1
        ? (size.width - barWidth) / (count - 1)
        : size.width;
    final radius = Radius.circular(barWidth / 2);
    final phase = level.time * 1000 / 130;
    final paint = Paint()
      ..color = InboxPalette.brand400.withValues(alpha: 0.55 + lvl * 0.45);
    final centerY = size.height / 2;

    for (var i = 0; i < count; i++) {
      final shape = InboxMotion.barShape(phase, i);
      final wobble = math.sin(phase * 0.7 + i * 0.9);
      final height = InboxMotion.recorderBar(lvl, shape, wobble);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * spacing, centerY - height / 2, barWidth, height),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RecorderWavePainter oldDelegate) =>
      oldDelegate.paused != paused || oldDelegate.bars != bars;
}

/// The halo around the recorder pill: `0 0 0 (level*5)px rgba(danger, .16+lvl*.2)`.
class RecorderHalo extends StatelessWidget {
  const RecorderHalo({
    super.key,
    required this.level,
    required this.paused,
    required this.radius,
  });

  final InboxAudioLevel level;
  final bool paused;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _HaloPainter(level: level, paused: paused, radius: radius),
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({
    required this.level,
    required this.paused,
    required this.radius,
  }) : super(repaint: level);

  final InboxAudioLevel level;
  final bool paused;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (paused) return;
    final lvl = level.value;
    if (lvl <= 0.01) return;
    final spread = InboxMotion.haloSpread(lvl);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = spread
      ..color = InboxPalette.danger.withValues(
        alpha: InboxMotion.haloAlpha(lvl),
      );
    final rect = (Offset.zero & size).deflate(spread / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter oldDelegate) =>
      oldDelegate.paused != paused || oldDelegate.radius != radius;
}
