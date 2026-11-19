import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';

/// The empty-search character: a magnifier with a face that scans, blinks and
/// puffs a little breath when it finds nothing.
///
/// Two controllers (scan 4.4 s, blink 4.2 s), one painter, one
/// `RepaintBoundary`. The letters drifting away are taken from the query the
/// user actually typed, so the state is *about* their search.
class SearchLensMascot extends StatefulWidget {
  const SearchLensMascot({super.key, required this.query, this.size = 150});

  final String query;
  final double size;

  @override
  State<SearchLensMascot> createState() => _SearchLensMascotState();
}

class _SearchLensMascotState extends State<SearchLensMascot>
    with TickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: ExploreMotion.mascotScan,
  )..repeat();

  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: ExploreMotion.mascotBlink,
  )..repeat();

  @override
  void dispose() {
    _scan.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reducedMotion(context);
    final letters = _letters(widget.query);

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: reduce
            ? CustomPaint(
                painter: _LensPainter(scan: 0, blink: 0, letters: letters),
              )
            : AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[_scan, _blink]),
                builder: (context, _) => CustomPaint(
                  painter: _LensPainter(
                    scan: _scan.value,
                    blink: _blink.value,
                    letters: letters,
                  ),
                ),
              ),
      ),
    );
  }

  static List<String> _letters(String query) {
    final cleaned = query.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    return cleaned.split('').take(8).toList(growable: false);
  }
}

class _LensPainter extends CustomPainter {
  const _LensPainter({
    required this.scan,
    required this.blink,
    required this.letters,
  });

  final double scan;
  final double blink;
  final List<String> letters;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 150;
    final center = Offset(size.width / 2, size.height / 2 - 4 * scale);

    // ── dashed halo, slowly turning
    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..color = ExplorePalette.haloViolet.withValues(alpha: 0.55);
    const dashes = 28;
    for (var i = 0; i < dashes; i++) {
      final start = (i / dashes) * math.pi * 2 + scan * math.pi * 0.4;
      const sweep = (math.pi * 2 / dashes) * 0.55;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 62 * scale),
        start,
        sweep,
        false,
        haloPaint,
      );
    }

    // ── the lens and its handle scan together
    final swing = math.sin(scan * math.pi * 2);
    canvas.save();
    canvas.translate(center.dx + swing * 9 * scale, center.dy);
    canvas.rotate(swing * 0.16);

    final lensRadius = 36 * scale;
    final lensRect = Rect.fromCircle(center: Offset.zero, radius: lensRadius);
    canvas.drawCircle(
      Offset.zero,
      lensRadius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[ExplorePalette.lensFace, ExplorePalette.lensFaceEnd],
        ).createShader(lensRect),
    );
    canvas.drawCircle(
      Offset.zero,
      lensRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * scale
        ..color = ExplorePalette.lensRim,
    );

    canvas.drawLine(
      Offset(25 * scale, 25 * scale),
      Offset(43 * scale, 43 * scale),
      Paint()
        ..strokeWidth = 11 * scale
        ..strokeCap = StrokeCap.round
        ..color = ExplorePalette.brand500,
    );

    // ── face
    final eyeScale = _eyeScale(blink);
    final eyePaint = Paint()..color = ExplorePalette.lensInk;
    for (final dx in <double>[-11, 11]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(dx * scale, -3 * scale),
          width: 7 * scale,
          height: 7 * scale * eyeScale,
        ),
        eyePaint,
      );
    }
    final mouth = Path()
      ..moveTo(-7 * scale, 9 * scale)
      ..quadraticBezierTo(0, 13 * scale, 7 * scale, 9 * scale);
    canvas.drawPath(
      mouth,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * scale
        ..strokeCap = StrokeCap.round
        ..color = ExplorePalette.lensInk,
    );
    canvas.restore();

    // ── puffs of breath, out of phase
    for (var i = 0; i < 3; i++) {
      final t = (scan + i / 3) % 1;
      canvas.drawCircle(
        Offset(
          center.dx + (i.isEven ? 40 : -34) * scale,
          center.dy + (26 + t * 26) * scale,
        ),
        (3.5 + t * 5) * scale,
        Paint()..color = Colors.white.withValues(alpha: (1 - t) * 0.7),
      );
    }

    // ── the typed letters, drifting up and away
    for (var i = 0; i < letters.length; i++) {
      final phase = (scan + i * 0.17) % 1;
      final painter = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            fontSize: 14 * scale,
            fontWeight: FontWeight.w900,
            color: ExplorePalette.driftLetter.withValues(
              alpha: (1 - phase).clamp(0.0, 1.0) * 0.9,
            ),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final angle = i * 0.9;
      painter.paint(
        canvas,
        Offset(
          center.dx + math.cos(angle) * (48 + i * 2.0) * scale,
          center.dy -
              18 * scale -
              phase * 46 * scale +
              math.sin(angle) * 20 * scale,
        ),
      );
    }
  }

  static double _eyeScale(double blink) {
    if (blink < 0.92) return 1;
    final t = (blink - 0.92) / 0.08;
    return 1 - math.sin(t * math.pi) * 0.88;
  }

  @override
  bool shouldRepaint(_LensPainter oldDelegate) =>
      oldDelegate.scan != scan ||
      oldDelegate.blink != blink ||
      oldDelegate.letters.length != letters.length;
}
