import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The backdrop: one deep gradient and two soft radial glows.
///
/// Two radial gradients painted once, no `BackdropFilter`, no blur — the whole
/// update page costs the same as a plain colour because nothing here repaints.
class UpdateAurora extends StatelessWidget {
  const UpdateAurora({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF1A1030),
              Color(0xFF120B22),
              Color(0xFF0B0716),
            ],
            stops: <double>[0, 0.55, 1],
          ),
        ),
        child: CustomPaint(
          size: Size.infinite,
          painter: const _AuroraPainter(),
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final violet = Paint()
      ..shader =
          RadialGradient(
            colors: <Color>[
              const Color(0xFF7B5FED).withValues(alpha: 0.38),
              const Color(0xFF7B5FED).withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.10),
              radius: size.width * 0.85,
            ),
          );
    canvas.drawRect(Offset.zero & size, violet);

    final cyan = Paint()
      ..shader =
          RadialGradient(
            colors: <Color>[
              const Color(0xFF3BA9FF).withValues(alpha: 0.18),
              const Color(0xFF3BA9FF).withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.92, size.height * 0.62),
              radius: size.width * 0.7,
            ),
          );
    canvas.drawRect(Offset.zero & size, cyan);
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) => false;
}

/// The halo behind the app mark: one ring that grows and fades, forever, plus a
/// still hairline ring so the shape never disappears between pulses.
class UpdateHaloPainter extends CustomPainter {
  const UpdateHaloPainter({required this.t});

  /// 0…1, one loop every 2.6 s.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Still ring.
    canvas.drawCircle(
      center,
      size.width * 0.34,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFB9A9F5).withValues(alpha: 0.22),
    );

    // Two pulses, half a loop apart, so the halo never looks like it stalled.
    for (var i = 0; i < 2; i++) {
      final phase = (t + i / 2) % 1;
      final radius = size.width * (0.34 + phase * 0.16);
      final fade = (1 - phase) * 0.5;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFFB9A9F5).withValues(alpha: fade),
      );
    }

    // A faint arc rotating slowly, for life.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width * 0.46),
      t * math.pi * 2,
      math.pi * 0.28,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF8B7BF0).withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(UpdateHaloPainter oldDelegate) => oldDelegate.t != t;
}
