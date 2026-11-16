import 'package:material_ui/material_ui.dart';

/// The icon set of the reference, kept as geometry rather than as a font.
///
/// The Material icon font draws similar shapes but not *these* shapes — the
/// bell's shoulder, the magnifier's 2.1 px stroke, the ECG spike. The paths are
/// copied straight from `pulse-home-reference-v4.html` so the app renders the
/// approved artwork, and they scale with the widget instead of a fixed glyph
/// size.
class PulseIcon extends StatelessWidget {
  const PulseIcon({
    super.key,
    required this.paths,
    required this.size,
    required this.color,
    this.strokeWidth = 2.1,
    this.viewBox = const Size(24, 24),
  });

  /// Shapes in [viewBox] units.
  final List<PulseShape> paths;
  final double size;
  final Color color;
  final double strokeWidth;
  final Size viewBox;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PulseIconPainter(
          shapes: paths,
          color: color,
          strokeWidth: strokeWidth,
          viewBox: viewBox,
        ),
      ),
    );
  }
}

/// A polyline / circle in the icon's own coordinate system.
class PulseShape {
  const PulseShape.path(this.d) : circle = null;
  const PulseShape.circle({required this.circle}) : d = null;

  /// SVG-ish path text in the same grammar the reference uses: `M`, `h`, `l`,
  /// `L`, `H`, `V`, `Z` and circles as their own primitive.
  final String? d;
  final PulseCircle? circle;
}

class PulseCircle {
  const PulseCircle(this.cx, this.cy, this.r);
  final double cx;
  final double cy;
  final double r;
}

/// The shapes the app currently draws, transcribed from the reference.
class PulseIcons {
  PulseIcons._();

  static const search = <PulseShape>[
    PulseShape.circle(circle: PulseCircle(11, 11, 7.2)),
    PulseShape.path('M16.6 16.8 L21 21.2'),
  ];

  static const close = <PulseShape>[PulseShape.path('M6 6 L18 18 M18 6 L6 18')];

  static const warning = <PulseShape>[
    PulseShape.path('M12 3.5 L21 20 H3 L12 3.5 Z'),
    PulseShape.path('M12 9.5 v4.2 M12 16.6 v.1'),
  ];

  static const shieldCheck = <PulseShape>[
    PulseShape.path(
      'M12 3.8 L4.8 6.6 v5.1 c0 4.2 3 7.6 7.2 8.9 4.2 -1.3 7.2 -4.7 7.2 -8.9 '
      'V6.6 L12 3.8 Z',
    ),
    PulseShape.path('M9 11.8 l2.1 2.1 l4 -4'),
  ];

  static const peopleAdd = <PulseShape>[
    PulseShape.path(
      'M4.5 20.5 v-1.8 c0 -2.4 2.4 -4.2 5.6 -4.2 s5.6 1.8 5.6 4.2 v1.8',
    ),
    PulseShape.circle(circle: PulseCircle(10.1, 7.6, 3.4)),
    PulseShape.path('M19.5 20.5 v-1.4 c0 -1.6 -1.1 -2.9 -2.9 -3.4'),
  ];

  static const clock = <PulseShape>[
    PulseShape.path('M12 4 v9 l5.2 3'),
    PulseShape.circle(circle: PulseCircle(12, 12, 8.4)),
  ];

  static const bell = <PulseShape>[
    PulseShape.path(
      'M6.2 9.6 a5.8 5.8 0 0 1 11.6 0 v3.1 c0 .9 .4 1.7 1 2.3 l.6 .6 H4.6 '
      'l.6 -.6 c.6 -.6 1 -1.4 1 -2.3 V9.6 Z',
    ),
    PulseShape.path('M9.6 19 a2.6 2.6 0 0 0 4.8 0'),
  ];
}

class _PulseIconPainter extends CustomPainter {
  _PulseIconPainter({
    required this.shapes,
    required this.color,
    required this.strokeWidth,
    required this.viewBox,
  });

  final List<PulseShape> shapes;
  final Color color;
  final double strokeWidth;
  final Size viewBox;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / viewBox.width;
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final shape in shapes) {
      final circle = shape.circle;
      if (circle != null) {
        canvas.drawCircle(Offset(circle.cx, circle.cy), circle.r, paint);
      } else {
        canvas.drawPath(svgPath(shape.d!), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PulseIconPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.shapes != shapes;
}

/// Tiny SVG path reader — enough for the grammar the reference icons use
/// (`M`, `L`, `H`, `V`, `h`, `l`, `a`, `c`, `v`, `Z`).
Path svgPath(String d) {
  final path = Path();
  var cx = 0.0;
  var cy = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  // Last cubic control point, for the smooth (s/S) variants.
  var lastCtrlX = 0.0;
  var lastCtrlY = 0.0;
  var hadCubic = false;

  final token = RegExp(r'([MmLlHhVvAaCcSsZz])|(-?\d*\.?\d+(?:e-?\d+)?)');

  final parts = <String>[];
  for (final m in token.allMatches(d)) {
    parts.add(m.group(0)!);
  }

  var index = 0;
  String? command;

  num next() => num.parse(parts[index++]);

  while (index < parts.length) {
    final p = parts[index];
    if (RegExp(r'[A-Za-z]').hasMatch(p)) {
      command = p;
      index++;
      if (command == 'Z' || command == 'z') {
        path.close();
        cx = startX;
        cy = startY;
        continue;
      }
    }
    switch (command) {
      case 'M':
        cx = next().toDouble();
        cy = next().toDouble();
        startX = cx;
        startY = cy;
        path.moveTo(cx, cy);
        command = 'L'; // implicit lineto after a moveto
      case 'm':
        cx += next().toDouble();
        cy += next().toDouble();
        startX = cx;
        startY = cy;
        path.moveTo(cx, cy);
        command = 'l';
      case 'L':
        cx = next().toDouble();
        cy = next().toDouble();
        path.lineTo(cx, cy);
      case 'l':
        cx += next().toDouble();
        cy += next().toDouble();
        path.lineTo(cx, cy);
      case 'H':
        cx = next().toDouble();
        path.lineTo(cx, cy);
      case 'h':
        cx += next().toDouble();
        path.lineTo(cx, cy);
      case 'V':
        cy = next().toDouble();
        path.lineTo(cx, cy);
      case 'v':
        cy += next().toDouble();
        path.lineTo(cx, cy);
      case 'C':
        final x1 = next().toDouble();
        final y1 = next().toDouble();
        final x2 = next().toDouble();
        final y2 = next().toDouble();
        final x = next().toDouble();
        final y = next().toDouble();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        hadCubic = true;
        cx = x;
        cy = y;
      case 'c':
        final x1 = cx + next().toDouble();
        final y1 = cy + next().toDouble();
        final x2 = cx + next().toDouble();
        final y2 = cy + next().toDouble();
        final x = cx + next().toDouble();
        final y = cy + next().toDouble();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        hadCubic = true;
        cx = x;
        cy = y;
      case 'S':
      case 's':
        final relative = command == 's';
        final x2 = relative ? cx + next().toDouble() : next().toDouble();
        final y2 = relative ? cy + next().toDouble() : next().toDouble();
        final x = relative ? cx + next().toDouble() : next().toDouble();
        final y = relative ? cy + next().toDouble() : next().toDouble();
        // Reflect the previous control point through the current point.
        final x1 = hadCubic ? 2 * cx - lastCtrlX : cx;
        final y1 = hadCubic ? 2 * cy - lastCtrlY : cy;
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        hadCubic = true;
        cx = x;
        cy = y;
      case 'A':
        final rx = next().toDouble();
        final ry = next().toDouble();
        next(); // x-axis rotation
        next(); // large-arc flag
        final sweep = next().toInt() == 1;
        final x = next().toDouble();
        final y = next().toDouble();
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          clockwise: sweep,
        );
        cx = x;
        cy = y;
      case 'a':
        final rx = next().toDouble();
        final ry = next().toDouble();
        next();
        next();
        final sweep = next().toInt() == 1;
        final x = cx + next().toDouble();
        final y = cy + next().toDouble();
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          clockwise: sweep,
        );
        cx = x;
        cy = y;
      default:
        index++; // never loop forever on something unexpected
    }
  }

  return path;
}
