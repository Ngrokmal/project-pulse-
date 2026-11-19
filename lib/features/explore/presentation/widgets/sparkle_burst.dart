import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';

/// A tiny controller a card can hold, so a burst can be triggered by code that
/// has no business knowing how the sparks are drawn.
class SparkleController extends ChangeNotifier {
  int _tick = 0;
  int get tick => _tick;

  void play() {
    _tick++;
    notifyListeners();
  }
}

/// Twelve sparks leaving an avatar, 620–900 ms on the ease-out curve.
///
/// The angles and distances are baked once (seeded, not `Random()` per frame),
/// so every frame is just arithmetic on a precomputed list and the painter can
/// live behind a `RepaintBoundary`.
class SparkleBurst extends StatefulWidget {
  const SparkleBurst({super.key, required this.controller, this.warm = true});

  final SparkleController controller;

  /// Every third spark is warm instead of cyan, like the reference.
  final bool warm;

  @override
  State<SparkleBurst> createState() => _SparkleBurstState();
}

class _SparkleBurstState extends State<SparkleBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Spark> _sparks;

  @override
  void initState() {
    super.initState();
    _sparks = _buildSparks();
    _controller = AnimationController(
      vsync: this,
      duration: ExploreMotion.sparkLife,
    );
    widget.controller.addListener(_play);
  }

  @override
  void didUpdateWidget(covariant SparkleBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_play);
      widget.controller.addListener(_play);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_play);
    _controller.dispose();
    super.dispose();
  }

  void _play() {
    if (!mounted || AppMotion.reducedMotion(context)) return;
    _controller.forward(from: 0);
  }

  List<_Spark> _buildSparks() {
    final random = math.Random(7);
    return List<_Spark>.generate(ExploreMotion.sparkCount, (i) {
      final angle =
          (math.pi * 2 * i) / ExploreMotion.sparkCount +
          random.nextDouble() * 0.45;
      final distance =
          ExploreMotion.sparkTravel * (0.72 + random.nextDouble() * 0.6);
      return _Spark(
        angle: angle,
        distance: distance,
        warm: widget.warm && i % 3 == 0,
        size: 3.2 + random.nextDouble() * 2.4,
      );
    }, growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.value == 0 || _controller.value == 1) {
              return const SizedBox.shrink();
            }
            return CustomPaint(
              painter: _BurstPainter(
                progress: _controller.value,
                sparks: _sparks,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Spark {
  const _Spark({
    required this.angle,
    required this.distance,
    required this.warm,
    required this.size,
  });

  final double angle;
  final double distance;
  final bool warm;
  final double size;
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({required this.progress, required this.sparks});

  final double progress;
  final List<_Spark> sparks;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final eased = ExploreMotion.easeOut.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final spark in sparks) {
      final reach = spark.distance * eased;
      final offset = Offset(
        center.dx + math.cos(spark.angle) * reach,
        center.dy + math.sin(spark.angle) * reach,
      );
      paint.color =
          (spark.warm ? const Color(0xFFFFC98A) : ExplorePalette.haloCyan)
              .withValues(alpha: fade);
      canvas.drawCircle(offset, spark.size * fade, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
