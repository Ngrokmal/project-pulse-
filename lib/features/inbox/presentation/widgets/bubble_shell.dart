import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// The bubble itself: gradient for mine, white with a hairline for theirs, with
/// the reference's corner logic:
///
/// * 18 px radius, 7 px tail on the side the bubble speaks from,
/// * `stackPrev` / `stackNext` pull the shared corners in to 8 px.
///
/// The shell is decoration only — content and animations live in the children,
/// so a 60 fps child never repaints the shadow.
class BubbleShell extends StatelessWidget {
  const BubbleShell({
    super.key,
    required this.child,
    required this.mine,
    this.stackPrev = false,
    this.stackNext = false,
    this.padding = InboxMotion.bubblePadding,
    this.playing = false,
    this.failed = false,
    this.sweep = false,
    this.maxWidth,
  });

  final Widget child;
  final bool mine;
  final bool stackPrev;
  final bool stackNext;
  final EdgeInsets padding;
  final bool playing;
  final bool failed;
  final bool sweep;
  final double? maxWidth;

  BorderRadius get _radius {
    const base = InboxMotion.bubbleRadius;
    const tail = InboxMotion.bubbleTail;
    const stacked = InboxMotion.bubbleStack;
    final top = stackPrev ? stacked : base;
    final bottom = stackNext ? stacked : base;
    return BorderRadius.only(
      topLeft: Radius.circular(top),
      topRight: Radius.circular(top),
      bottomLeft: Radius.circular(mine ? bottom : tail),
      bottomRight: Radius.circular(mine ? tail : bottom),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = _radius;
    final decoration = BoxDecoration(
      gradient: mine ? InboxPalette.brand : null,
      color: mine ? null : Colors.white,
      border: mine ? null : Border.all(color: InboxPalette.hairline),
      borderRadius: radius,
      boxShadow: failed
          ? const [
              BoxShadow(
                color: Color(0x332A0E6B),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ]
          : playing
          ? InboxPalette.bubblePlaying
          : mine
          ? InboxPalette.bubbleOut
          : InboxPalette.bubbleIn,
    );

    Widget content = Padding(padding: padding, child: child);

    if (sweep) {
      content = Stack(
        children: [
          content,
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(borderRadius: radius, child: const _SendSweep()),
            ),
          ),
        ],
      );
    }

    return Container(
      constraints: maxWidth == null
          ? null
          : BoxConstraints(maxWidth: maxWidth!),
      decoration: decoration,
      child: content,
    );
  }
}

/// `@keyframes sendSweep`: a 104° white band crossing the bubble once, 900 ms,
/// 60 ms after it appears — the "this just left your composer" signal.
class _SendSweep extends StatefulWidget {
  const _SendSweep();

  @override
  State<_SendSweep> createState() => _SendSweepState();
}

class _SendSweepState extends State<_SendSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: InboxMotion.sendSweep,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(InboxMotion.sendSweepDelay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value;
        return FractionalTranslation(
          translation: Offset(-1.3 + 2.6 * t, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-1, -0.35),
                end: const Alignment(1, 0.35),
                colors: [
                  Colors.white.withValues(alpha: 0),
                  Colors.white.withValues(alpha: 0.5),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0.28, 0.48, 0.68],
              ),
            ),
          ),
        );
      },
    );
  }
}
