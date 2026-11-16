import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/inbox_delivery.dart';
import '../../domain/inbox_palette.dart';

/// The tick that lives inside a bubble.
///
/// * `pending` – one check, blinking at 1.4 s (the message is on its way),
/// * `sent` – one check, calm,
/// * `seen` – two checks in the reference cyan, with a soft glow,
/// * `failed` – no tick at all; the bubble itself turns red and shows a badge.
class DeliveryTicks extends StatelessWidget {
  const DeliveryTicks({super.key, required this.state, required this.mine});

  final InboxDelivery state;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    if (state == InboxDelivery.failed) return const SizedBox.shrink();

    final base = mine ? Colors.white : AppColors.brand600;
    final color = state == InboxDelivery.seen ? InboxPalette.cyan : base;
    final double opacity = switch (state) {
      InboxDelivery.pending => 0.85,
      InboxDelivery.sent => 0.78,
      InboxDelivery.seen => 1,
      InboxDelivery.failed => 0,
    };

    final ticks = CustomPaint(
      size: const Size(16, 11),
      painter: _TicksPainter(
        color: color.withValues(alpha: opacity),
        doubleTick: state == InboxDelivery.seen,
        glow: state == InboxDelivery.seen,
      ),
    );

    if (state != InboxDelivery.pending) return ticks;

    return _Blink(child: ticks);
  }
}

/// `@keyframes tickBlink`: .45 → 1 → .45 over 1.4 s.
class _Blink extends StatefulWidget {
  const _Blink({required this.child});

  final Widget child;

  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          Opacity(opacity: 0.45 + 0.55 * _controller.value, child: child),
      child: widget.child,
    );
  }
}

class _TicksPainter extends CustomPainter {
  const _TicksPainter({
    required this.color,
    required this.doubleTick,
    required this.glow,
  });

  final Color color;
  final bool doubleTick;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (glow) {
      paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
    }

    final s = size.height / 11;
    canvas.scale(s);

    // First check: 1,7 → 4,10 → 9.5,3 (reference path).
    final first = Path()
      ..moveTo(1, 6.7)
      ..lineTo(4.2, 9.9)
      ..lineTo(doubleTick ? 9.2 : 10.6, 2.4);
    canvas.drawPath(first, paint);

    if (doubleTick) {
      final second = Path()
        ..moveTo(7.4, 6.7)
        ..lineTo(10.6, 9.9)
        ..lineTo(17, 2.4);
      canvas.drawPath(second, paint);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.doubleTick != doubleTick ||
      oldDelegate.glow != glow;
}
