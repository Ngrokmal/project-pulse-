import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../../../core/motion/pulse_motion.dart';

/// Which slice of the inbox is on screen.
enum InboxFilter {
  all('all', 'All'),
  chats('chat', 'Chats'),
  groups('group', 'Groups');

  const InboxFilter(this.kind, this.label);

  /// Matches `Conversation.kind` ('direct' chats are the `chat` side).
  final String kind;
  final String label;

  bool accepts(String conversationKind) => switch (this) {
    InboxFilter.all => true,
    InboxFilter.chats => conversationKind != 'group',
    InboxFilter.groups => conversationKind == 'group',
  };
}

/// The All · Chats · Groups control from the reference, complete with the
/// gradient pill that glides between tabs on a spring, its 4.6 s sheen, and the
/// count chip that pops slightly when its tab is the active one.
///
/// Counts are real (and show `0` when a side is empty) — nothing is hardcoded.
class PulseSegments extends StatefulWidget {
  const PulseSegments({
    super.key,
    required this.selected,
    required this.allCount,
    required this.chatCount,
    required this.groupCount,
    required this.onChanged,
  });

  final InboxFilter selected;
  final int allCount;
  final int chatCount;
  final int groupCount;
  final ValueChanged<InboxFilter> onChanged;

  @override
  State<PulseSegments> createState() => _PulseSegmentsState();
}

class _PulseSegmentsState extends State<PulseSegments>
    with SingleTickerProviderStateMixin {
  static const double _pad = 6;
  static const double _gap = 7;

  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
  )..repeat();

  int get _index => InboxFilter.values.indexOf(widget.selected);

  int _countFor(InboxFilter f) => switch (f) {
    InboxFilter.all => widget.allCount,
    InboxFilter.chats => widget.chatCount,
    InboxFilter.groups => widget.groupCount,
  };

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      child: ClipRRect(
        // BackdropFilter needs a clip; 999 radius reads as a capsule.
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(_pad),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFECEAF4).withValues(alpha: 0.9),
                  ),
                  // The reference's `0 12px 28px -24px rgba(42,14,107,.9)` is a
                  // sliver once the spread eats the capsule, and Skia paints that
                  // sliver as a hard grey band straight across the glass. Keep the
                  // intent — a whisper of a drop so the pill floats — but with no
                  // negative spread and an alpha low enough not to grey the
                  // translucent fill.
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2A0E6B).withValues(alpha: 0.045),
                      offset: const Offset(0, 10),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final count = InboxFilter.values.length;
                    final width =
                        (constraints.maxWidth - _gap * (count - 1)) / count;

                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 500),
                          curve: const Cubic(0.34, 1.56, 0.4, 1),
                          left: _index * (width + _gap),
                          top: 0,
                          width: width,
                          height: _buttonHeight,
                          child: _Pill(sheen: _sheen),
                        ),
                        Row(
                          children: [
                            for (final f in InboxFilter.values) ...[
                              if (f.index > 0) const SizedBox(width: _gap),
                              Expanded(
                                child: _Seg(
                                  label: f.label,
                                  count: _countFor(f),
                                  active: f == widget.selected,
                                  onTap: () => widget.onChanged(f),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              // `inset 0 1px 0 rgba(255,255,255,.9)` — the glass highlight
              // riding the top edge of the capsule.
              Positioned(
                left: 34,
                right: 34,
                top: 0.7,
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.9),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 9 + 15 px line + 9 — the reference's `padding: 9px 4px`.
  static const double _buttonHeight = 38;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.sheen});

  final Animation<double> sheen;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              PulseMotion.segmentPillStart,
              PulseMotion.segmentPillMid,
              PulseMotion.segmentPillEnd,
            ],
            stops: [0, 0.55, 1],
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5F3FDC).withValues(alpha: 0.72),
              offset: const Offset(0, 12),
              blurRadius: 24,
              spreadRadius: -10,
            ),
          ],
        ),
        child: Stack(
          children: [
            // the travelling sheen: off-left until 55 %, across by 80 %
            Positioned.fill(
              child: AnimatedBuilder(
                animation: sheen,
                builder: (context, _) {
                  final t = sheen.value;
                  final x = t <= 0.55
                      ? -1.2
                      : (t >= 0.80 ? 1.2 : -1.2 + 2.4 * ((t - 0.55) / 0.25));
                  return FractionalTranslation(
                    translation: Offset(x, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: const Alignment(-0.72, -0.3),
                          end: const Alignment(0.72, 0.3),
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.42),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.20, 0.48, 0.72],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Seg extends StatefulWidget {
  const _Seg({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Seg> createState() => _SegState();
}

class _SegState extends State<_Seg> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.active,
      label: '${widget.label}, ${widget.count}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            height: _PulseSegmentsState._buttonHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: widget.active
                        ? Colors.white
                        : const Color(0xFF5B5870),
                  ),
                  child: Text(widget.label),
                ),
                const SizedBox(width: 7),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  constraints: const BoxConstraints(minWidth: 21),
                  height: 21,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.active
                        ? Colors.white.withValues(alpha: 0.26)
                        : const Color(0xFFDDD8EE),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: AnimatedScale(
                    scale: widget.active ? 1.06 : 1,
                    duration: const Duration(milliseconds: 340),
                    curve: PulseMotion.spring,
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.6,
                        color: widget.active
                            ? Colors.white
                            : const Color(0xFF6B6880),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
