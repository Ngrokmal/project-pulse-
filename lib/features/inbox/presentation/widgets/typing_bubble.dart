import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// The three-dot bubble that appears while the peer types.
class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: InboxMotion.bubbleInFast,
      curve: InboxMotion.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: InboxPalette.hairline),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(7),
          ),
          boxShadow: InboxPalette.bubbleIn,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(delay: 0),
            SizedBox(width: 4),
            _Dot(delay: 130),
            SizedBox(width: 4),
            _Dot(delay: 260),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delay});

  final int delay;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: InboxMotion.typeDot,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 0 %,60 %,100 %: y 0, opacity .45 · 30 %: y −5, opacity 1.
        final t = _controller.value;
        final wave = t <= 0.3
            ? t / 0.3
            : (t <= 0.6 ? 1 - (t - 0.3) / 0.3 : 0.0);
        return Opacity(
          opacity: 0.45 + 0.55 * wave,
          child: Transform.translate(
            offset: Offset(0, -5 * wave),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: InboxPalette.brand300,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
