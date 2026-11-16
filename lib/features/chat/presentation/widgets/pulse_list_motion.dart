import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../../../core/motion/pulse_motion.dart';

/// One row of a Pulse list: the staggered entrance (blur → sharp, rise →
/// settle) from the reference.
///
/// The controller *is* the delay — a single ticker whose curve starts at the
/// row's slot in the stagger, so nothing schedules a `Timer` and a widget test
/// never fails on a pending one.
class PulseRowMotion extends StatefulWidget {
  const PulseRowMotion({
    super.key,
    required this.index,
    required this.child,
    this.seenKey,
  });

  /// Position in the list; drives the 26 ms stagger.
  final int index;
  final Widget child;

  /// Identity of the row's content (a conversation id).
  ///
  /// The entrance belongs to a row's *first* appearance. Slivers rebuild and
  /// recycle elements while scrolling, so without this a row that scrolls into
  /// view would replay the whole blur-in — which reads as a glitch, not motion.
  final String? seenKey;

  @override
  State<PulseRowMotion> createState() => _PulseRowMotionState();
}

class _PulseRowMotionState extends State<PulseRowMotion>
    with SingleTickerProviderStateMixin {
  /// Rows that have already made their entrance in this session.
  static final Set<String> _seen = <String>{};

  AnimationController? _enter;
  late Animation<double> _enterT;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;

    // A row built while the list is already scrolled is *arriving*, not making
    // an entrance — it appears at rest. Only the first batch (built at offset
    // 0) gets the staggered bloom.
    final position = Scrollable.maybeOf(context)?.position;
    final alreadyScrolled = position != null && position.pixels > 0.5;
    final key = widget.seenKey;

    if (alreadyScrolled || (key != null && !_seen.add(key))) {
      _enterT = const AlwaysStoppedAnimation<double>(1);
      return;
    }

    final stagger = PulseMotion.rowStagger.inMilliseconds * widget.index;
    final total = PulseMotion.rowEnter.inMilliseconds + stagger;
    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    _enter = controller;
    _enterT = CurvedAnimation(
      parent: controller,
      curve: Interval(stagger / total, 1, curve: PulseMotion.easeOut),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _enter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _enterT,
      builder: (context, child) {
        final t = _enterT.value;
        final out = 1 - t;
        if (t >= 1) return child!;

        final dy = out * PulseMotion.rowEnterRise;
        final scale = 1 - (1 - PulseMotion.rowEnterScale) * out;
        final sigma = PulseMotion.blur(out * 7) / 2;

        Widget content = Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            child: Opacity(opacity: t, child: child),
          ),
        );

        if (sigma > 0.05) {
          content = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: content,
          );
        }
        return content;
      },
      child: widget.child,
    );
  }
}

/// The soft top and bottom edges of the scrolling list: content dissolves into
/// the page instead of being cut off by a hard clip.
///
/// One [ShaderMask] for the whole list (a single save-layer) rather than per-row
/// opacity — this is what makes the fade continuous as rows travel.
class PulseEdgeFade extends StatelessWidget {
  const PulseEdgeFade({
    super.key,
    required this.child,
    this.top = PulseMotion.featherTop,
    this.bottom = PulseMotion.featherBottom,
  });

  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final h = rect.height;
        if (h <= top + bottom) {
          // Too short to feather — keep everything visible.
          return const LinearGradient(colors: [Color(0xFFFFFFFF)])
              .createShader(rect);
        }
        final topStop = top / h;
        final bottomStop = 1 - bottom / h;
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, topStop, bottomStop, 1],
        ).createShader(Rect.fromLTWH(0, 0, rect.width, h));
      },
      child: child,
    );
  }
}

/// Keeps a row's identity while the list around it reorders (tab switch, search
/// spotlight) and glides it from where it used to be to where it now belongs.
///
/// The reference does this with `getBoundingClientRect()` before and after the
/// mutation (`rowShift`: translateY → 0, scale .987 → 1, blur 2.6 → 0 over
/// 560 ms on the spring). The equivalent here measures in *content* space — the
/// row's top plus the scroll offset — so a concurrent scroll cannot fake a move.
class PulseFlip extends StatefulWidget {
  const PulseFlip({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  State<PulseFlip> createState() => _PulseFlipState();
}

class _PulseFlipState extends State<PulseFlip>
    with SingleTickerProviderStateMixin {
  /// Where each row sat last time we looked, in content coordinates.
  static final Map<String, double> _tops = <String, double>{};

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PulseMotion.rowShiftMs,
  );
  double _shift = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(PulseFlip old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;

      final scroll = Scrollable.maybeOf(context)?.position.pixels ?? 0;
      final top = box.localToGlobal(Offset.zero).dy + scroll;
      final previous = _tops[widget.id];
      _tops[widget.id] = top;

      if (previous == null) return; // first appearance: the entrance owns it
      final dy = previous - top;
      // Anything larger than a few rows is a stale measurement from a row that
      // was culled off-screen, not a glide.
      if (dy.abs() < 1.5 || dy.abs() > 420) return;

      _shift = dy;
      _c.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value;
        if (v >= 1 || _shift == 0) return child!;

        final eased = PulseMotion.spring.transform(v);
        final dy = _shift * (1 - eased);
        final scale = 0.987 + 0.013 * eased;
        final sigma =
            PulseMotion.blur(2.6 * (1 - (v / 0.6).clamp(0.0, 1.0))) / 2;

        Widget content = Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(scale: scale, child: child),
        );
        if (sigma > 0.05) {
          content = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: content,
          );
        }
        return content;
      },
      child: widget.child,
    );
  }
}
