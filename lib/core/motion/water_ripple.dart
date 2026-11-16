import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'pulse_motion.dart';

/// A tappable surface with the v4 "water" feedback:
///
/// * the card sinks 2.5 px and scales to .99 while the finger is down,
/// * on release it springs back up with a small overshoot,
/// * a droplet blooms from the exact point of contact, two water rings run
///   outward and three beads of spray fly off the impact point.
///
/// Everything is painted on the CPU (one [CustomPaint] per burst) so there is
/// no backdrop filter and no extra compositing layer per frame.
class PulseTapSurface extends StatefulWidget {
  const PulseTapSurface({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.semanticsLabel,
    this.semanticsHint,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final String? semanticsLabel;
  final String? semanticsHint;

  @override
  State<PulseTapSurface> createState() => _PulseTapSurfaceState();
}

class _PulseTapSurfaceState extends State<PulseTapSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: PulseMotion.pressIn,
  );

  final List<Widget> _bursts = [];
  int _nextBurst = 0;

  /// Where the finger landed — used to cancel the feedback when a press turns
  /// into a scroll.
  Offset _downAt = Offset.zero;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  /// Pointer-down, not `onTapDown`: a tap recogniser only fires once it has won
  /// the gesture arena (i.e. on release), which would make the sink and the
  /// droplet appear a beat late. A raw listener reacts on contact, like the
  /// reference does.
  void _onDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _downAt = event.localPosition;
    _press.animateTo(1, curve: Curves.easeOut);

    final id = _nextBurst++;
    setState(() {
      _bursts.add(
        _WaterBurst(
          key: ValueKey<int>(id),
          origin: event.localPosition,
          onDone: () {
            if (!mounted) return;
            setState(
              () => _bursts.removeWhere((b) => b.key == ValueKey<int>(id)),
            );
          },
        ),
      );
    });
  }

  void _onMove(PointerMoveEvent event) {
    if ((event.localPosition - _downAt).distance > 12) _onRelease();
  }

  void _onRelease() {
    if (!widget.enabled || _press.value == 0) return;
    // Overshoot past 0 → the card rises ~1.8 px above rest and settles.
    _press.animateBack(
      0,
      duration: PulseMotion.rowLift,
      curve: Curves.easeOutBack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget surface = AnimatedBuilder(
      animation: _press,
      builder: (context, child) {
        final v = _press.value;
        return Transform.translate(
          offset: Offset(0, PulseMotion.pressSink * v),
          child: Transform.scale(
            scale: 1 - (1 - PulseMotion.pressScale) * v,
            child: child,
          ),
        );
      },
      child: widget.child,
    );

    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: (_) => _onRelease(),
        onPointerCancel: (_) => _onRelease(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              surface,
              for (final burst in _bursts)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        PulseMotion.rowRadius,
                      ),
                      child: burst,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaterBurst extends StatefulWidget {
  const _WaterBurst({super.key, required this.origin, required this.onDone});

  final Offset origin;
  final VoidCallback onDone;

  @override
  State<_WaterBurst> createState() => _WaterBurstState();
}

class _WaterBurstState extends State<_WaterBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: PulseMotion.ripple)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _RipplePainter(
          origin: widget.origin,
          elapsedMs: _c.value * PulseMotion.ripple.inMilliseconds,
        ),
      ),
    );
  }
}

/// Paints the droplet, the two rings and the three beads for one tap.
class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.origin, required this.elapsedMs});

  final Offset origin;
  final double elapsedMs;

  static const Cubic _dropCurve = Cubic(0.18, 0.7, 0.32, 1);
  static const double _base = PulseMotion.rippleBase / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final dropT = (elapsedMs / PulseMotion.drop.inMilliseconds).clamp(0.0, 1.0);
    if (dropT < 1) _paintDrop(canvas, dropT);

    _paintRing(
      canvas,
      elapsedMs / PulseMotion.ringWave.inMilliseconds,
      0xB393C8F2, // clear water — a cool specular rim, never brand purple
      glint: true,
    );
    _paintRing(
      canvas,
      (elapsedMs - PulseMotion.ringWaveDelay.inMilliseconds) /
          PulseMotion.ringWaveTwo.inMilliseconds,
      0x8CB6DCFA,
    );

    _paintBeads(canvas);
  }

  void _paintDrop(Canvas canvas, double t) {
    final eased = _dropCurve.transform(t);
    final radius = _base * ui.lerpDouble(0.22, 6.2, eased)!;
    final fade = t < 0.45
        ? 1.0
        : ui.lerpDouble(0.92, 0.0, ((t - 0.45) / 0.55).clamp(0.0, 1.0))!;

    final shader = ui.Gradient.radial(
      origin,
      radius,
      <Color>[
        const Color(0xFFFFFFFF).withValues(alpha: 1.0 * fade),
        const Color(0xFFFFFFFF).withValues(alpha: 0.78 * fade),
        const Color(0xFFE8F4FF).withValues(alpha: 0.55 * fade),
        const Color(0xFFC6E0FC).withValues(alpha: 0.30 * fade),
        const Color(0xFFA6CDF3).withValues(alpha: 0.14 * fade),
        const Color(0xFFA6CDF3).withValues(alpha: 0.0),
      ],
      const <double>[0.0, 0.16, 0.34, 0.56, 0.72, 0.86],
    );

    canvas.drawCircle(origin, radius, Paint()..shader = shader);
  }

  /// [glint] adds a thin white highlight just inside the rim — the detail that
  /// makes a colourless ripple readable on a pale card.
  void _paintRing(Canvas canvas, double t, int argb, {bool glint = false}) {
    final rt = t.clamp(0.0, 1.0);
    if (rt <= 0 || rt >= 1) return;

    final radius = _base * ui.lerpDouble(0.5, 6.3, rt)!;
    final stroke = ui.lerpDouble(2.6, 0.9, rt)!;
    final alpha = (1 - rt) * (rt < 0.6 ? 1.0 : 0.6);

    final rim = Color(argb).withValues(alpha: (Color(argb).a) * alpha);
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = rim,
    );

    if (!glint) return;
    canvas.drawCircle(
      origin,
      radius - stroke * 0.62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.42
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85 * alpha),
    );
  }

  void _paintBeads(Canvas canvas) {
    const offsets = <Offset>[Offset(-30, -18), Offset(26, -22), Offset(12, 24)];

    for (var i = 0; i < offsets.length; i++) {
      final start = i * PulseMotion.beadStagger.inMilliseconds;
      final t = ((elapsedMs - start) / PulseMotion.bead.inMilliseconds).clamp(
        0.0,
        1.0,
      );
      if (t <= 0 || t >= 1) continue;

      final eased = Curves.easeOutCubic.transform(t);
      final centre = origin + offsets[i] * eased;
      final radius = ui.lerpDouble(4.0, 4.8, eased)!;
      final alpha = t < 0.25 ? t / 0.25 : (1 - (t - 0.25) / 0.75);

      final shader = ui.Gradient.radial(
        centre,
        radius,
        <Color>[
          const Color(0xFFFFFFFF).withValues(alpha: 0.95 * alpha),
          const Color(0xFFE2F1FF).withValues(alpha: 0.75 * alpha),
          const Color(0xFFC6E0FC).withValues(alpha: 0.0),
        ],
        const <double>[0.0, 0.52, 0.85],
      );

      canvas.drawCircle(centre, radius, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.elapsedMs != elapsedMs || oldDelegate.origin != origin;
}
