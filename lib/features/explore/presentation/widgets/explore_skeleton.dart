import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';

/// Placeholder rows with one soft band sweeping across them.
///
/// Used while a list loads and while a search is in flight, so waiting has a
/// shape and the sheet never shows an empty rectangle for 400 ms. A single
/// controller drives every row, and the whole thing sits in a
/// `RepaintBoundary`.
class ExploreSkeleton extends StatefulWidget {
  const ExploreSkeleton({super.key, this.rows = 3, this.showHeader = false});

  final int rows;
  final bool showHeader;

  @override
  State<ExploreSkeleton> createState() => _ExploreSkeletonState();
}

class _ExploreSkeletonState extends State<ExploreSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ExploreMotion.skeletonSweep,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reducedMotion(context);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final shift = _controller.value * 2 - 1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showHeader) ...[
                _ShimmerBand(
                  shift: reduce ? -1 : shift,
                  child: Row(
                    children: [
                      const _Bone(width: 14, height: 14, radius: 7),
                      const SizedBox(width: 8),
                      _Bone(
                        width: 150,
                        height: 10,
                        radius: 5,
                        shift: reduce ? -1 : shift,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              for (var i = 0; i < widget.rows; i++) ...[
                _SkeletonRow(shift: reduce ? -1 : shift, index: i),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.shift, required this.index});

  final double shift;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ExploreMotion.cardRadius),
        border: Border.all(color: ExplorePalette.hairline),
      ),
      child: _ShimmerBand(
        shift: shift,
        child: Row(
          children: [
            _Bone(width: 42, height: 42, radius: 14, shift: shift),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bone(
                    width: index.isEven ? 132 : 108,
                    height: 11,
                    radius: 6,
                    shift: shift,
                  ),
                  const SizedBox(height: 7),
                  _Bone(
                    width: index.isEven ? 84 : 96,
                    height: 9,
                    radius: 5,
                    shift: shift,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Bone(width: 58, height: 33, radius: 11, shift: shift),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBand extends StatelessWidget {
  const _ShimmerBand({required this.child, required this.shift});

  final Widget child;
  final double shift;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const <Color>[
          Color(0x00FFFFFF),
          Color(0xCCFFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: const <double>[0.42, 0.5, 0.58],
        transform: _Shift(shift * rect.width * 0.6),
      ).createShader(rect),
      child: child,
    );
  }
}

class _Shift extends GradientTransform {
  const _Shift(this.dx);
  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

class _Bone extends StatelessWidget {
  const _Bone({
    required this.width,
    required this.height,
    required this.radius,
    this.shift = 0,
  });

  final double width;
  final double height;
  final double radius;
  final double shift;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEFEBFA),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
