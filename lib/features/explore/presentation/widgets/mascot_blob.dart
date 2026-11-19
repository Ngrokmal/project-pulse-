import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';

/// The little violet character that lives in Explore's empty states.
///
/// It is calm on purpose: a slow 5.6 s float, a blink every 4.6 s, two halos
/// breathing out of phase, three satellites drifting. Two controllers drive all
/// of it — one for the body, one for the eyelids — and the whole thing sits
/// behind a `RepaintBoundary` with a painter that only repaints when a value
/// actually changes.
class MascotBlob extends StatefulWidget {
  const MascotBlob({super.key, this.size = 132});

  final double size;

  @override
  State<MascotBlob> createState() => _MascotBlobState();
}

class _MascotBlobState extends State<MascotBlob> with TickerProviderStateMixin {
  late final AnimationController _body = AnimationController(
    vsync: this,
    duration: ExploreMotion.mascotBob,
  )..repeat();

  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: ExploreMotion.mascotBlink,
  )..repeat();

  @override
  void dispose() {
    _body.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reducedMotion(context)) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: const _MascotPainter(body: 0, blink: 0)),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[_body, _blink]),
          builder: (context, _) => CustomPaint(
            painter: _MascotPainter(body: _body.value, blink: _blink.value),
          ),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter({required this.body, required this.blink});

  final double body;
  final double blink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.width / 132;
    final phase = body * math.pi * 2;

    // ── halos: two rings breathing out of phase
    for (var i = 0; i < 2; i++) {
      final t = (body + (i == 0 ? 0 : 0.5)) % 1;
      final radius = (46 + t * 14) * scale;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * scale
        ..color = (i == 0 ? ExplorePalette.haloViolet : ExplorePalette.haloCyan)
            .withValues(alpha: (1 - t) * 0.55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCircle(center: center, radius: radius),
          Radius.circular(radius * 0.62),
        ),
        paint,
      );
    }

    // ── satellites: three dots on slow orbits
    final satellites = <(double, double, Color)>[
      (29, 7.5, ExplorePalette.brand300),
      (35, 12, ExplorePalette.haloCyan),
      (32, 4.2, const Color(0xFFFFC98A)),
    ];
    for (var i = 0; i < satellites.length; i++) {
      final (radius, dot, color) = satellites[i];
      final angle = phase * (i.isEven ? 1 : -1) + i * 2.1;
      final offset = Offset(
        center.dx + math.cos(angle) * radius * scale,
        center.dy + math.sin(angle) * radius * scale * 0.9,
      );
      canvas.drawCircle(
        offset,
        dot * scale,
        Paint()..color = color.withValues(alpha: 0.85),
      );
    }

    // ── the body floats 4 px on a sine
    final float = math.sin(phase) * 4 * scale;
    final blob = Rect.fromCenter(
      center: center.translate(0, float),
      width: 84 * scale,
      height: 82 * scale,
    );
    final blobRRect = RRect.fromRectAndRadius(
      blob,
      Radius.circular(30 * scale),
    );
    canvas.drawRRect(
      blobRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            ExplorePalette.mascotBlobStart,
            ExplorePalette.mascotBlobEnd,
          ],
        ).createShader(blob)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * scale),
    );
    canvas.drawRRect(
      blobRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            ExplorePalette.mascotBlobStart,
            ExplorePalette.mascotBlobEnd,
          ],
        ).createShader(blob),
    );

    // ── cheeks
    final cheekPaint = Paint()..color = ExplorePalette.mascotCheek;
    for (final dx in <double>[-21, 21]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            center.dx + dx * scale,
            center.dy + float + 12 * scale,
          ),
          width: 13 * scale,
          height: 7.5 * scale,
        ),
        cheekPaint,
      );
    }

    // ── eyes: closed for 5 % of every 4.6 s
    final eyeScale = _eyeScale(blink);
    final eyePaint = Paint()..color = Colors.white;
    for (final dx in <double>[-15, 15]) {
      final eyeRect = Rect.fromCenter(
        center: Offset(center.dx + dx * scale, center.dy + float - 1 * scale),
        width: 9 * scale,
        height: 12 * scale * eyeScale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(eyeRect, Radius.circular(5 * scale)),
        eyePaint,
      );
    }

    // ── smile: 18 → 23 px wide, slow
    final smileWidth = (18 + 5 * (0.5 + 0.5 * math.sin(phase * 0.5))) * scale;
    final smile = Path()
      ..moveTo(center.dx - smileWidth / 2, center.dy + float + 15 * scale)
      ..quadraticBezierTo(
        center.dx,
        center.dy + float + 15 * scale + 9 * scale,
        center.dx + smileWidth / 2,
        center.dy + float + 15 * scale,
      );
    canvas.drawPath(
      smile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * scale
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
  }

  /// `scaleY(.12)` at 95 % of the blink cycle.
  static double _eyeScale(double blink) {
    if (blink < 0.93) return 1;
    final t = (blink - 0.93) / 0.07; // 0..1
    final dip = math.sin(t * math.pi);
    return 1 - dip * 0.88;
  }

  @override
  bool shouldRepaint(_MascotPainter oldDelegate) =>
      oldDelegate.body != body || oldDelegate.blink != blink;
}
