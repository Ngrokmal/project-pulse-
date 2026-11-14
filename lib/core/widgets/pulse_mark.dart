import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';

/// Original PULSE brand mark: a speech bubble with a heartbeat waveform.
/// Painted as a vector path (same geometry as assets/brand/src/pulse_mark.svg)
/// so it stays crisp at any size and ships no extra bytes.
class PulseMark extends StatelessWidget {
  const PulseMark({
    super.key,
    this.size = 64,
    this.gradient = AppColors.primaryGradient,
    this.glow = false,
  });

  final double size;
  final Gradient gradient;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Pulse',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _PulseMarkPainter(gradient: gradient, glow: glow),
        ),
      ),
    );
  }
}

class _PulseMarkPainter extends CustomPainter {
  const _PulseMarkPainter({required this.gradient, required this.glow});

  final Gradient gradient;
  final bool glow;

  /// Design-space canvas is 200×200 (identical to the SVG source).
  static const double _design = 200;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _design;
    canvas.save();
    canvas.scale(scale);

    final bubble = Path()
      ..moveTo(70, 26)
      ..lineTo(130, 26)
      ..arcToPoint(
        const Offset(174, 70),
        radius: const Radius.circular(44),
        clockwise: true,
      )
      ..lineTo(174, 106)
      ..arcToPoint(
        const Offset(130, 150),
        radius: const Radius.circular(44),
        clockwise: true,
      )
      ..lineTo(112, 150)
      ..lineTo(80, 180)
      ..lineTo(88, 150)
      ..lineTo(70, 150)
      ..arcToPoint(
        const Offset(26, 106),
        radius: const Radius.circular(44),
        clockwise: true,
      )
      ..lineTo(26, 70)
      ..arcToPoint(
        const Offset(70, 26),
        radius: const Radius.circular(44),
        clockwise: true,
      )
      ..close();

    final fill = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(26, 26, 148, 164))
      ..isAntiAlias = true;

    if (glow) {
      canvas.drawPath(
        bubble,
        Paint()
          ..color = AppColors.brand500.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }
    canvas.drawPath(bubble, fill);

    final beat = Path()
      ..moveTo(56, 90)
      ..lineTo(74, 90)
      ..lineTo(84, 64)
      ..lineTo(96, 114)
      ..lineTo(106, 78)
      ..lineTo(114, 90)
      ..lineTo(144, 90);

    canvas.drawPath(
      beat,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PulseMarkPainter old) =>
      old.gradient != gradient || old.glow != glow;
}

/// Wordmark: mark + "Pulse", used on splash / welcome.
class PulseWordmark extends StatelessWidget {
  const PulseWordmark({
    super.key,
    this.markSize = 64,
    this.fontSize = 34,
    this.color = Colors.white,
    this.showTagline = false,
    this.tagline,
  });

  final double markSize;
  final double fontSize;
  final Color color;
  final bool showTagline;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PulseMark(size: markSize, glow: true),
        SizedBox(height: markSize * 0.18),
        Text(
          'Pulse',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            height: 1.05,
            letterSpacing: -0.8,
            color: color,
            shadows: [
              Shadow(
                color: AppColors.navy900.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 8),
          Text(
            tagline ?? 'Chat · Call · Connect',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: fontSize * 0.40,
              fontWeight: FontWeight.w500,
              letterSpacing: 2.4,
              color: color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ],
    );
  }
}
