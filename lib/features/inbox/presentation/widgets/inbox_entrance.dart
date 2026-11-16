import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';

/// `@keyframes bubbleIn`: opacity 0→1, translateY 24→0, scale .93→1 and a 7 px
/// blur that clears at 55 %. Runs once, and only for rows that are actually new
/// — scrolling back through history must not re-animate anything.
class InboxEntrance extends StatefulWidget {
  const InboxEntrance({
    super.key,
    required this.child,
    this.duration = InboxMotion.bubbleIn,
    this.delay = Duration.zero,
    this.slide = 24,
    this.scaleFrom = 0.93,
    this.blur = 7,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;
  final double slide;
  final double scaleFrom;
  final double blur;

  @override
  State<InboxEntrance> createState() => _InboxEntranceState();
}

class _InboxEntranceState extends State<InboxEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: InboxMotion.easeOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return widget.child;

    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        final blurSigma = widget.blur * (1 - (t / 0.55).clamp(0.0, 1.0));
        Widget result = child!;
        if (blurSigma > 0.05) {
          result = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
            ),
            child: result,
          );
        }
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.slide * (1 - t)),
            child: Transform.scale(
              scale: widget.scaleFrom + (1 - widget.scaleFrom) * t,
              child: result,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
