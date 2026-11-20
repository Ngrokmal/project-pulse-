import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';

/// The word `Explore`, alive.
///
/// Two things happen to it and nothing else: it arrives once (620 ms, fade +
/// 8 px rise), then a single soft highlight travels across the letters every
/// 4.2 s — the same sheen the segmented control and the inbox header use, so the
/// whole app reads as one motion system. The gradient itself never moves, so the
/// word stays legible at every frame.
class ExploreWordmark extends StatefulWidget {
  const ExploreWordmark({super.key, this.text = 'Explore', this.fontSize = 30});

  final String text;
  final double fontSize;

  @override
  State<ExploreWordmark> createState() => _ExploreWordmarkState();
}

class _ExploreWordmarkState extends State<ExploreWordmark>
    with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: ExploreMotion.wordmarkSweep,
  );

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: ExploreMotion.wordmarkEnter,
  );

  @override
  void initState() {
    super.initState();
    _sweep.repeat();
    _enter.forward();
  }

  @override
  void dispose() {
    _sweep.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reducedMotion(context);

    final word = Text(
      widget.text,
      style: TextStyle(
        fontSize: widget.fontSize,
        height: 1.05,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.1,
        color: Colors.white,
      ),
    );

    final painted = reduce
        ? ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => ExplorePalette.brand.createShader(rect),
            child: word,
          )
        : AnimatedBuilder(
            animation: _sweep,
            builder: (context, child) {
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const <Color>[
                    Color(0xFF6B4BE0),
                    Color(0xFF8B6BF0),
                    Color(0xFFF2EAFF),
                    Color(0xFF8B6BF0),
                    Color(0xFF4F25C4),
                  ],
                  stops: const <double>[0, 0.4, 0.5, 0.6, 1],
                  transform: _SweepTransform(
                    (_sweep.value * 2 - 1) * rect.width * 0.85,
                  ),
                ).createShader(rect),
                child: child,
              );
            },
            child: word,
          );

    if (reduce) return painted;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _enter, curve: ExploreMotion.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.14),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _enter, curve: ExploreMotion.spring)),
        child: painted,
      ),
    );
  }
}

class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.dx);

  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}
