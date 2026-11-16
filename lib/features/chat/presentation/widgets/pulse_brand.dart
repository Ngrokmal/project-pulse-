import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/motion/pulse_icons.dart';
import '../../../../core/motion/pulse_motion.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// The Pulse mark: a gradient tile that beats, two rings leaving it, and an ECG
/// line that draws itself with a bright spark riding the wave.
///
/// Frame-for-frame port of `.logo` in the reference (2.6 s beat, 3 s rings,
/// 3.1 s wave).
class PulseLogo extends StatefulWidget {
  const PulseLogo({super.key, this.size = 44});

  final double size;

  @override
  State<PulseLogo> createState() => _PulseLogoState();
}

class _PulseLogoState extends State<PulseLogo> with TickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: PulseMotion.logoBeat,
  )..repeat();

  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: PulseMotion.logoRing,
  )..repeat();

  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: PulseMotion.waveDraw,
  )..repeat();

  /// 0 %, 72 %, 100 % at rest; a small double-thump in between.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween<double>(1), weight: 72),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.055,
      ).chain(CurveTween(curve: PulseMotion.easeOut)),
      weight: 6,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.055,
        end: 0.995,
      ).chain(CurveTween(curve: PulseMotion.easeOut)),
      weight: 6,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.995,
        end: 1.02,
      ).chain(CurveTween(curve: PulseMotion.easeOut)),
      weight: 6,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.02,
        end: 1,
      ).chain(CurveTween(curve: PulseMotion.easeOut)),
      weight: 10,
    ),
  ]).animate(_beat);

  @override
  void dispose() {
    _beat.dispose();
    _ring.dispose();
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final radius = size * (14 / 44);
    final waveW = size * (27 / 44);
    final waveH = size * (20 / 44);

    return AnimatedBuilder(
      animation: Listenable.merge([_beat, _ring, _wave]),
      builder: (context, _) {
        return Transform.scale(
          scale: _scale.value,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _Ring(t: _ring.value, radius: radius, size: size),
              _Ring(t: (_ring.value + 0.5) % 1, radius: radius, size: size),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.brand400,
                      AppColors.brand600,
                      AppColors.brand700,
                    ],
                    stops: [0, 0.55, 1],
                  ),
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5F3FDC).withValues(alpha: 0.75),
                      offset: const Offset(0, 10),
                      blurRadius: 22,
                      spreadRadius: -8,
                    ),
                  ],
                ),
                // The inset top highlight CSS gives us for free.
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: 1,
                    margin: EdgeInsets.symmetric(horizontal: radius * 0.55),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
              CustomPaint(
                size: Size(waveW, waveH),
                painter: _WavePainter(t: _wave.value),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.t, required this.radius, required this.size});

  final double t;
  final double radius;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 0 % → 100 % scale, 0 % → 70 % opacity.
    final eased = PulseMotion.ring.transform(t);
    final fade = 0.55 * (1 - PulseMotion.ring.transform(math.min(t / 0.7, 1)));

    return Transform.scale(
      scale: 1 + 0.52 * eased,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius * (16 / 14)),
          border: Border.all(
            color: const Color(0xFF7B5FED).withValues(alpha: 0.42 * fade),
            width: 1.6,
          ),
        ),
      ),
    );
  }
}

/// Base line + drawing stroke + travelling spark, all from the reference's
/// `pathLength="100"` dash maths.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.t});

  final double t;

  static final Path _path = svgPath(
    'M1 10.6 h4.1 l2.3 -6.1 l3.2 12 l2.9 -7.7 l1.8 3.4 h6.7',
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 27, size.height / 20);

    final metrics = _path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final total = metric.length;

    // ---- faint base
    canvas.drawPath(
      _path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.38)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // ---- the line draws itself (0–38 %), holds, then retracts (92–100 %)
    final drawT = t < 0.38
        ? const Cubic(0.4, 0, 0.2, 1).transform(t / 0.38)
        : (t < 0.92 ? 1.0 : 1 - (t - 0.92) / 0.08);
    final drawOpacity = t < 0.84 ? 1.0 : 0.25;

    if (drawT > 0.001) {
      final drawn = metric.extractPath(0, total * drawT);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.55 * drawOpacity)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawPath(drawn, glow);

      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: drawOpacity)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // ---- spark: a 10 % dash travelling the whole line (0–40 %)
    final sparkT = t / 0.40;
    if (sparkT > 0 && sparkT < 1.1) {
      final sparkOpacity = t < 0.06
          ? t / 0.06
          : (t < 0.40 ? 1.0 : (t < 0.44 ? 1 - (t - 0.40) / 0.04 : 0.0));
      if (sparkOpacity > 0.01) {
        final start = (sparkT.clamp(0.0, 1.0)) * total;
        final end = math.min(start + total * 0.1, total);
        if (end > start) {
          final spark = metric.extractPath(start, end);
          canvas.drawPath(
            spark,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = Colors.white.withValues(alpha: 0.95 * sparkOpacity)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
          );
          canvas.drawPath(
            spark,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = Colors.white.withValues(alpha: sparkOpacity)
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round,
          );
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.t != t;
}

/// "Pulse" — 27 px, w700, tight tracking, deep-ink navy.
class PulseWordmark extends StatelessWidget {
  const PulseWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Pulse',
      style: AppTypography.displaySmall.copyWith(
        fontSize: 27,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1,
        color: PulseMotion.wordmarkInk,
      ),
    );
  }
}

/// The 42 px header button of the reference: soft brand wash on hover, a quick
/// 0.9 squash on press, an optional slow bell shake and an optional count
/// badge that pops in.
class PulseIconButton extends StatefulWidget {
  const PulseIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.badgeCount = 0,
    this.wiggle = false,
    this.size = 42,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onPressed;
  final int badgeCount;
  final bool wiggle;
  final double size;

  @override
  State<PulseIconButton> createState() => _PulseIconButtonState();
}

class _PulseIconButtonState extends State<PulseIconButton>
    with TickerProviderStateMixin {
  bool _hovered = false;
  bool _down = false;

  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: PulseMotion.bellWiggle,
  );

  late final Animation<double> _shake = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween<double>(0), weight: 86),
    TweenSequenceItem(tween: ConstantTween<double>(0), weight: 2),
    TweenSequenceItem(tween: Tween<double>(begin: 0, end: -12), weight: 2),
    TweenSequenceItem(tween: Tween<double>(begin: -12, end: 10), weight: 2),
    TweenSequenceItem(tween: Tween<double>(begin: 10, end: -7), weight: 2),
    TweenSequenceItem(tween: Tween<double>(begin: -7, end: 4), weight: 2),
    TweenSequenceItem(tween: Tween<double>(begin: 4, end: 0), weight: 4),
  ]).animate(_wiggle);

  @override
  void initState() {
    super.initState();
    if (widget.wiggle) _wiggle.repeat();
  }

  @override
  void didUpdateWidget(PulseIconButton old) {
    super.didUpdateWidget(old);
    if (widget.wiggle && !_wiggle.isAnimating) {
      _wiggle.repeat();
    } else if (!widget.wiggle && _wiggle.isAnimating) {
      _wiggle.stop();
      _wiggle.value = 0;
    }
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _down ? 0.9 : 1,
            duration: const Duration(milliseconds: 180),
            curve: PulseMotion.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _hovered
                    ? AppColors.brand500.withValues(alpha: 0.09)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (context, child) => Transform.rotate(
                      angle: _shake.value * math.pi / 180,
                      child: child,
                    ),
                    child: widget.icon,
                  ),
                  if (widget.badgeCount > 0)
                    Positioned(
                      top: 2,
                      right: 1,
                      child: _Badge(
                        count: widget.badgeCount,
                        label: widget.label,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The red count badge: 18 px tall, ringed in the page colour so it reads as
/// floating above the bell.
class _Badge extends StatefulWidget {
  const _Badge({required this.count, required this.label});

  final int count;
  final String label;

  @override
  State<_Badge> createState() => _BadgeState();
}

class _BadgeState extends State<_Badge> with SingleTickerProviderStateMixin {
  // The 350 ms wait is baked into the controller rather than scheduled as a
  // timer, so a widget test never ends with a pending one.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PulseMotion.badgeDelay + PulseMotion.badgePop,
  )..forward();

  late final Animation<double> _scale = CurvedAnimation(
    parent: _c,
    curve: Interval(
      PulseMotion.badgeDelay.inMilliseconds /
          (PulseMotion.badgeDelay + PulseMotion.badgePop).inMilliseconds,
      1,
      curve: PulseMotion.spring,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.count > 99 ? '99+' : '${widget.count}';
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _c,
        child: Container(
          constraints: const BoxConstraints(minWidth: 18),
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: AppColors.danger,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(color: const Color(0xFFFBFAFF), spreadRadius: 2.5),
              BoxShadow(
                color: AppColors.danger.withValues(alpha: 0.5),
                offset: const Offset(0, 4),
                blurRadius: 10,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}
