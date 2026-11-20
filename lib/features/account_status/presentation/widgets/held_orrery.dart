import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The animated seal of the hold notice: three tilted orbits with one traveller
/// each, a slow brake arc around the outside, and a core that holds a pause —
/// or, once the appeal is in, a check.
///
/// It is one [CustomPainter] driven by two controllers, not a tree of animated
/// widgets: orbits, travellers, glow and sparks are all painted in the same
/// frame, so the cost is flat no matter how many of them are on screen.
class HeldOrrery extends StatefulWidget {
  const HeldOrrery({
    super.key,
    required this.received,
    this.size = 264,
    this.reduceMotion = false,
  });

  /// True once the appeal is filed: the orbits speed up, the ink turns mint and
  /// the pause becomes a check.
  final bool received;

  final double size;

  /// Honours the OS "remove animations" setting: the composition stays, the
  /// movement stops.
  final bool reduceMotion;

  @override
  State<HeldOrrery> createState() => _HeldOrreryState();
}

class _HeldOrreryState extends State<HeldOrrery> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _orbit;
  late final AnimationController _spark;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );
    _spark = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    if (widget.reduceMotion) {
      _intro.value = 1;
    } else {
      _intro.forward();
      _orbit.repeat();
    }
    if (widget.received) _spark.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant HeldOrrery oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.reduceMotion != oldWidget.reduceMotion) {
      if (widget.reduceMotion) {
        _orbit.stop();
        _intro.value = 1;
      } else {
        _orbit.repeat();
      }
    }

    if (widget.received && !oldWidget.received) {
      if (widget.reduceMotion) {
        _spark.value = 1;
      } else {
        _spark.forward(from: 0);
      }
      // Faster orbits: the same system, now working.
      _orbit
        ..stop()
        ..duration = const Duration(seconds: 11)
        ..repeat();
    } else if (!widget.received && oldWidget.received) {
      _orbit
        ..stop()
        ..duration = const Duration(seconds: 20)
        ..repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _orbit.dispose();
    _spark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.received
          ? 'Appeal received. The seal is open.'
          : 'Account on hold. The seal is closed.',
      image: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _orbit, _spark]),
            builder: (context, _) => CustomPaint(
              painter: _OrreryPainter(
                intro: _intro.value,
                orbit: _orbit.value,
                spark: _spark.value,
                received: widget.received,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrreryPainter extends CustomPainter {
  _OrreryPainter({
    required this.intro,
    required this.orbit,
    required this.spark,
    required this.received,
  });

  final double intro;
  final double orbit;
  final double spark;
  final bool received;

  // The palette of the notice. Amber while held, mint once it is in.
  static const _amber = Color(0xFFF7B267);
  static const _rose = Color(0xFFFF7A90);
  static const _mint = Color(0xFF3BE59B);

  Color get _ink => received ? _mint : const Color(0xFFF2C6A0);
  Color get _line =>
      received ? const Color(0x593BE59B) : const Color(0x4DFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final eased = Curves.easeOutCubic.transform(intro.clamp(0.0, 1.0));

    _paintGlow(canvas, center, r, eased);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(0.86 + 0.14 * eased);
    canvas.translate(-center.dx, -center.dy);

    _paintOrbits(canvas, center, r, eased);
    _paintBrake(canvas, center, r, eased);
    _paintCore(canvas, center, r, eased);
    if (received) _paintBurst(canvas, center, r);
    if (received && spark > 0) _paintSparks(canvas, center, r);

    canvas.restore();
  }

  // ---------------------------------------------------------------- backdrop
  void _paintGlow(Canvas canvas, Offset center, double r, double eased) {
    final pulse = received ? 0.5 + 0.5 * math.sin(orbit * math.pi * 4) : 1.0;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          (received ? _mint : _rose).withValues(alpha: 0.30 * eased),
          (received ? _mint : const Color(0xFF7B5FED)).withValues(
            alpha: 0.10 * eased,
          ),
          const Color(0x00000000),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.95));
    canvas.drawCircle(center, r * 0.95, glow);

    if (!received) {
      // The heartbeat: two thin rings breathing out of the core.
      for (var i = 0; i < 2; i++) {
        final t = ((orbit * 4 + i * 0.5) % 1.0);
        final radius = r * (0.30 + 0.42 * t);
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = _amber.withValues(alpha: (1 - t) * 0.20 * eased);
        canvas.drawCircle(center, radius, ring);
      }
    } else {
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _mint.withValues(alpha: 0.18 + 0.14 * pulse);
      canvas.drawCircle(center, r * 0.62, halo);
    }
  }

  // ------------------------------------------------------------------ orbits
  void _paintOrbits(Canvas canvas, Offset center, double r, double eased) {
    // rx, ry, tilt, traveller speed (cycles per 20 s), direction
    const orbitSpecs = [
      (0.94, 0.34, -0.42, 1.18, 1.0),
      (0.83, 0.45, 0.62, -0.74, -1.0),
      (0.66, 0.26, 0.18, 0.42, 1.0),
    ];

    for (var index = 0; index < orbitSpecs.length; index++) {
      final (rx, ry, tilt, speed, direction) = orbitSpecs[index];
      final wobble = received
          ? 1.0
          : 1.0 + 0.015 * math.sin(orbit * 2 * math.pi);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      canvas.scale(1, (ry / rx) * wobble);

      final radius = r * rx;
      final path = Path()
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: radius));

      // Draw-in: each orbit unwinds from nothing.
      final draw = ((eased * 1.35) - index * 0.14).clamp(0.0, 1.0);
      if (draw > 0) {
        final metric = path.computeMetrics().first;
        canvas.drawPath(
          metric.extractPath(0, metric.length * draw),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = index == 2 ? 0.9 : 1.1
            ..color = _line.withValues(
              alpha: (index == 2 ? 0.55 : 0.85) * eased,
            ),
        );
      }
      canvas.restore();

      // The traveller rides the same ellipse, in un-tilted space.
      if (draw >= 0.999) {
        final angle =
            (orbit * speed * direction + index * 0.37) * 2 * math.pi * 4;
        final local = Offset(
          math.cos(angle) * r * rx,
          math.sin(angle) * r * rx * (ry / rx) * wobble,
        );
        final point = _rotate(local, tilt) + center;
        final dotColor = received ? _mint : const Color(0xFFFFE6C9);

        canvas.drawCircle(
          point,
          r * 0.085,
          Paint()
            ..shader = RadialGradient(
              colors: [
                dotColor.withValues(alpha: 0.55),
                const Color(0x00000000),
              ],
            ).createShader(Rect.fromCircle(center: point, radius: r * 0.085)),
        );
        canvas.drawCircle(
          point,
          r * 0.022,
          Paint()
            ..color = dotColor
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.4),
        );
      }
    }
  }

  // ------------------------------------------------------------------- brake
  void _paintBrake(Canvas canvas, Offset center, double r, double eased) {
    if (received) return;
    final start = orbit * 2 * math.pi * 2 - math.pi / 2;
    final rect = Rect.fromCircle(center: center, radius: r * 0.97);
    canvas.drawArc(
      rect,
      start,
      0.52 * eased,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..color = _amber.withValues(alpha: 0.72),
    );
  }

  // -------------------------------------------------------------------- core
  void _paintCore(Canvas canvas, Offset center, double r, double eased) {
    final coreR = r * (0.40 - 0.05 * (1 - eased));
    final disc = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.45),
        colors: received
            ? const [Color(0xFF1C6B4E), Color(0xFF0B2E23), Color(0xFF06120E)]
            : const [Color(0xFF2A2440), Color(0xFF141126), Color(0xFF0A0814)],
      ).createShader(Rect.fromCircle(center: center, radius: coreR));

    canvas.drawCircle(center, coreR, disc);

    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = _ink.withValues(alpha: 0.28 * eased),
    );

    // Inner hairline ring, the seam of the seal.
    canvas.drawCircle(
      center,
      coreR * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _ink.withValues(alpha: 0.16 * eased),
    );

    _paintMark(canvas, center, coreR, eased);
  }

  /// Shield with a pause (held) or a check (received).
  void _paintMark(Canvas canvas, Offset center, double coreR, double eased) {
    final scale = coreR / 52;
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = _ink.withValues(alpha: 0.95 * eased);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    // The shield, drawn for a 52 px radius core.
    final shield = Path()
      ..moveTo(0, -29.5)
      ..lineTo(25, -21)
      ..lineTo(25, -1.8)
      ..quadraticBezierTo(25, 19.3, 0, 31.6)
      ..quadraticBezierTo(-25, 19.3, -25, -1.8)
      ..lineTo(-25, -21)
      ..close();
    canvas.drawPath(shield, ink);

    final progress = (eased * 1.2).clamp(0.0, 1.0);
    if (!received) {
      // Two bars: the pause is the whole point of the screen.
      final barHeight = 14.0 * progress;
      for (final dx in [-5.6, 5.6]) {
        canvas.drawLine(
          Offset(dx, -barHeight / 2),
          Offset(dx, barHeight / 2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6 * scale
            ..strokeCap = StrokeCap.round
            ..color = _ink.withValues(alpha: 0.9 * eased),
        );
      }
    } else {
      // A check that draws itself, on the same 1.4 s the sparks take.
      final t = Curves.easeOutCubic.transform(progress);
      final check = Path()
        ..moveTo(-15.5, 0.5)
        ..lineTo(-4, 12)
        ..lineTo(16.5, -9.5);
      final metric = check.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 * scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = _mint,
      );
    }

    canvas.restore();
  }

  // ------------------------------------------------------------------- sparks
  void _paintBurst(Canvas canvas, Offset center, double r) {
    final t = spark;
    if (t <= 0 || t >= 1) return;
    final eased = Curves.easeOutCubic.transform(t);
    canvas.drawCircle(
      center,
      r * (0.40 + 0.75 * eased),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * (1 - eased)
        ..color = _mint.withValues(alpha: (1 - eased) * 0.55),
    );
  }

  void _paintSparks(Canvas canvas, Offset center, double r) {
    final t = spark;
    if (t <= 0 || t >= 1) return;
    final eased = Curves.easeOutCubic.transform(t);
    const count = 16;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi + 0.22;
      final distance =
          r * (0.42 + 0.62 * eased) * (0.72 + 0.28 * ((i * 37) % 10) / 10);
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final radius = (2.6 * (1 - eased)) + 0.6;
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = _mint.withValues(alpha: (1 - eased) * 0.9),
      );
    }
  }

  static Offset _rotate(Offset p, double angle) => Offset(
    p.dx * math.cos(angle) - p.dy * math.sin(angle),
    p.dx * math.sin(angle) + p.dy * math.cos(angle),
  );

  @override
  bool shouldRepaint(covariant _OrreryPainter old) =>
      old.intro != intro ||
      old.orbit != orbit ||
      old.spark != spark ||
      old.received != received;
}
