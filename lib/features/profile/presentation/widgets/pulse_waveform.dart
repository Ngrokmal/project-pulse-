import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';

/// The heartbeat under the avatar.
///
/// One path is drawn twice: a quiet trace at 55 % opacity, and a short bright
/// segment that travels along it forever. Nothing here is a video or an asset —
/// it is a `PathMetric` walked by one animation controller, so it costs a single
/// painter and stops completely when the phone asks for reduced motion.
class PulseWaveform extends StatefulWidget {
  const PulseWaveform({super.key, this.height = 96, this.strokeWidth = 1.4});

  final double height;
  final double strokeWidth;

  @override
  State<PulseWaveform> createState() => _PulseWaveformState();
}

class _PulseWaveformState extends State<PulseWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5400),
  );

  bool _off = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _controller.stop();
      _controller.value = 0.35;
    } else if (!_off && !_controller.isAnimating) {
      _controller.repeat();
    }
    _off = reduce;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _WavePainter(
              progress: _controller.value,
              strokeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.progress, required this.strokeWidth});

  final double progress;
  final double strokeWidth;

  /// The same trace the v3 card uses, in a 340 × 120 box.
  static const List<double> _points = <double>[
    0, 78, 96, 78, 108, 78, 118, 46, 130, 108, 142, 62, 152, 78, 206, 78, //
    218, 78, 228, 40, 240, 112, 252, 56, 262, 78, 340, 78,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const sourceWidth = 340.0;
    const sourceHeight = 120.0;
    final path = Path();
    for (var i = 0; i < _points.length; i += 2) {
      final x = _points[i] / sourceWidth * size.width;
      final y = _points[i + 1] / sourceHeight * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawPath(path, base);

    // A gradient window walked along the path: the pulse "travels".
    final metric = path.computeMetrics().first;
    final total = metric.length;
    const window = 0.34;
    final start = (progress * (1 + window) - window) * total;
    final end = (progress * (1 + window)) * total;
    if (end <= 0 || start >= total) return;
    final clampedStart = start.clamp(0.0, total);
    final clampedEnd = end.clamp(0.0, total);
    final segment = metric.extractPath(clampedStart, clampedEnd);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 3
      ..strokeCap = StrokeCap.round
      ..color = AppColors.brand300.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(segment, glow);

    final bright = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 1.5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [AppColors.brand300, Colors.white, AppColors.blue300],
      ).createShader(Offset.zero & size);
    canvas.drawPath(segment, bright);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.strokeWidth != strokeWidth;
}
