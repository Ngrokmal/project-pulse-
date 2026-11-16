import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';

/// The tiny three dots that follow "typing" in the header
/// (`@keyframes typeDot`, 3 px, 1.15 s).
class TypingDotsInline extends StatefulWidget {
  const TypingDotsInline({super.key, required this.color});

  final Color color;

  @override
  State<TypingDotsInline> createState() => _TypingDotsInlineState();
}

class _TypingDotsInlineState extends State<TypingDotsInline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: InboxMotion.typeDot,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(3, (index) {
          final shifted = (_controller.value + index * 0.14) % 1.0;
          // 0 %,60 %,100 %: y 0 / opacity .28 · 30 %: y −2 / opacity 1.
          final wave = shifted <= 0.3
              ? shifted / 0.3
              : (shifted <= 0.6 ? 1 - (shifted - 0.3) / 0.3 : 0.0);
          return Padding(
            padding: EdgeInsets.only(left: index == 0 ? 0 : 2),
            child: Opacity(
              opacity: 0.28 + 0.72 * wave,
              child: Transform.translate(
                offset: Offset(0, -2 * wave),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
