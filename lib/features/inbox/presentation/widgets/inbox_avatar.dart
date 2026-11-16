import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

enum AvatarPresence { active, typing, offline }

/// The inbox avatar choreography from the reference:
///
/// * a conic ring that orbits every 4.8 s,
/// * a breathing halo (3.6 s),
/// * a tap ripple + pop,
/// * a presence dot that pulses while the peer types and goes grey when offline.
class InboxAvatar extends StatefulWidget {
  const InboxAvatar({
    super.key,
    required this.initials,
    required this.seed,
    required this.presence,
    this.size = 42,
    this.onTap,
  });

  final String initials;
  final String seed;
  final AvatarPresence presence;
  final double size;
  final VoidCallback? onTap;

  @override
  State<InboxAvatar> createState() => _InboxAvatarState();
}

class _InboxAvatarState extends State<InboxAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(
    vsync: this,
    duration: InboxMotion.avatarOrbit,
  )..repeat();
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: InboxMotion.avatarHalo,
  )..repeat();
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: InboxMotion.ripple,
  );
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  @override
  void dispose() {
    _orbit.dispose();
    _halo.dispose();
    _ripple.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _onTap() {
    _ripple.forward(from: 0);
    _pop.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final quiet = widget.presence == AvatarPresence.offline;
    final radius = widget.size * 0.36;

    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.size + 14,
        height: widget.size + 14,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // breathing halo
            if (!quiet)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _halo,
                  builder: (context, _) => CustomPaint(
                    painter: _HaloPainter(
                      progress: _halo.value,
                      radius: radius + 7,
                      color: InboxPalette.brand500,
                    ),
                  ),
                ),
              ),
            // orbiting ring
            if (!quiet)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _orbit,
                  builder: (context, _) => CustomPaint(
                    painter: _OrbitPainter(
                      angle: _orbit.value * 2 * math.pi,
                      radius: radius + 3,
                    ),
                  ),
                ),
              ),
            // the avatar itself
            AnimatedBuilder(
              animation: _pop,
              builder: (context, child) {
                final t = _pop.value;
                // 0 → 1, 38 % → 1.1 with a −2° tilt, 100 % → 1.
                final scale = t < 0.38
                    ? 1 + 0.1 * Curves.easeOut.transform(t / 0.38)
                    : 1 +
                          0.1 *
                              (1 -
                                  Curves.easeInOut.transform(
                                    (t - 0.38) / 0.62,
                                  ));
                return Transform.rotate(
                  angle: t < 0.38
                      ? -0.035 * (t / 0.38)
                      : -0.035 * (1 - t) / 0.62,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: _AvatarFace(
                initials: widget.initials,
                seed: widget.seed,
                size: widget.size,
                radius: radius,
              ),
            ),
            // tap ripple
            AnimatedBuilder(
              animation: _ripple,
              builder: (context, _) {
                if (_ripple.value == 0) return const SizedBox.shrink();
                return Transform.scale(
                  scale: 1 + 1.15 * Curves.easeOut.transform(_ripple.value),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: InboxPalette.brand500.withValues(
                          alpha: 0.6 * (1 - _ripple.value),
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                );
              },
            ),
            // presence dot
            Positioned(
              right: widget.size * 0.09,
              bottom: widget.size * 0.12,
              child: _PresenceDot(presence: widget.presence),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarFace extends StatelessWidget {
  const _AvatarFace({
    required this.initials,
    required this.seed,
    required this.size,
    required this.radius,
  });

  final String initials;
  final String seed;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: InboxPalette.avatarFor(seed),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D2A0E6B),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

class _PresenceDot extends StatefulWidget {
  const _PresenceDot({required this.presence});

  final AvatarPresence presence;

  @override
  State<_PresenceDot> createState() => _PresenceDotState();
}

class _PresenceDotState extends State<_PresenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: InboxMotion.presencePulse,
  );

  @override
  void initState() {
    super.initState();
    if (widget.presence == AvatarPresence.typing) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PresenceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.presence == AvatarPresence.typing && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (widget.presence != AvatarPresence.typing && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.presence != AvatarPresence.offline;
    final colorDot = online ? InboxPalette.brand500 : InboxPalette.ghost;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = online
            ? 0.2 +
                  (widget.presence == AvatarPresence.typing
                      ? 0.6 * _pulse.value
                      : 0)
            : 0.12;
        return Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: colorDot,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFCFBFF), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: colorDot.withValues(alpha: glow * 0.5),
                blurRadius: 0,
                spreadRadius: 1 + 4 * glow,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.angle, required this.radius});

  final double angle;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width - 6,
      height: size.height - 6,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6)
      ..shader = SweepGradient(
        colors: [
          InboxPalette.brand500.withValues(alpha: 0),
          InboxPalette.brand500.withValues(alpha: 0.95),
          InboxPalette.cyan.withValues(alpha: 0.98),
          InboxPalette.brand500.withValues(alpha: 0),
        ],
        stops: const [0, 0.2, 0.37, 0.58],
        transform: GradientRotation(angle - 1.5707963),
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + 3)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.radius != radius;
}

class _HaloPainter extends CustomPainter {
  const _HaloPainter({
    required this.progress,
    required this.radius,
    required this.color,
  });

  final double progress;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 0 %,100 %: 0 px spread → 55 %: 8 px, fading out along the way.
    final t = (progress / 0.55).clamp(0.0, 1.0);
    final spread = 8 * t;
    final alpha = 0.28 * (1 - t);
    if (alpha <= 0.002) return;
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width - 6,
      height: size.height - 6,
    ).inflate(spread);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius + 7 + spread)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
