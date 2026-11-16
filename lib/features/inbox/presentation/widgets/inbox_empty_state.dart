import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';

/// The reference's empty inbox: two chat bubbles floating at different speeds,
/// a breathing bloom behind them and three twinkling sparks.
///
/// Even the empty state is animated — a still screen here would read as broken.
class InboxEmptyState extends StatefulWidget {
  const InboxEmptyState({
    super.key,
    required this.peerName,
    required this.onSuggestion,
  });

  final String peerName;
  final ValueChanged<String> onSuggestion;

  static const List<String> suggestions = [
    'Hey! 👋',
    'How are you?',
    'Let’s catch up ☕',
  ];

  @override
  State<InboxEmptyState> createState() => _InboxEmptyStateState();
}

class _InboxEmptyStateState extends State<InboxEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  )..repeat();

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: InboxMotion.noteIn,
      curve: InboxMotion.spring,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: Transform.scale(scale: 0.95 + 0.05 * value, child: child),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 210,
            height: 180,
            child: AnimatedBuilder(
              animation: _float,
              builder: (context, _) =>
                  CustomPaint(painter: _EmptyArtPainter(_float.value)),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 16.5,
              height: 1.3,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: InboxPalette.ink,
            ),
          ),
          const SizedBox(height: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              'Say hello to ${widget.peerName} — your first message starts the story.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.8,
                height: 1.5,
                color: InboxPalette.muted,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < InboxEmptyState.suggestions.length; i++)
                _SuggestionChip(
                  label: InboxEmptyState.suggestions[i],
                  delay: Duration(milliseconds: i * 60),
                  onTap: () =>
                      widget.onSuggestion(InboxEmptyState.suggestions[i]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.delay,
    required this.onTap,
  });

  final String label;
  final Duration delay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: InboxMotion.noteIn,
      curve: InboxMotion.spring,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: InboxPalette.brand500.withValues(alpha: 0.22),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A2A0E6B),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: InboxPalette.brand700,
            ),
          ),
        ),
      ),
    );
  }
}

/// The art itself: gradients, tails and dots, all in one painter.
class _EmptyArtPainter extends CustomPainter {
  _EmptyArtPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // breathing bloom (4.6 s, scale 1 → 1.08)
    final bloomPhase = (t * 5.2 / 4.6) % 1.0;
    final bloomScale =
        1 + 0.08 * (0.5 - 0.5 * math.cos(2 * math.pi * bloomPhase));
    canvas.save();
    canvas.translate(center.dx, center.dy - 6);
    canvas.scale(bloomScale);
    canvas.drawCircle(
      Offset.zero,
      96,
      Paint()
        ..shader = RadialGradient(
          colors: [
            InboxPalette.brand500.withValues(alpha: 0.22),
            InboxPalette.brand500.withValues(alpha: 0),
          ],
          stops: const [0, 0.62],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 96)),
    );
    canvas.restore();

    // bubble A — floats 5.2 s, rotate −3° → 1°
    final aPhase = 0.5 - 0.5 * math.cos(2 * math.pi * t);
    canvas.save();
    canvas.translate(20, 42 - 9 * aPhase);
    canvas.rotate((-3 + 4 * aPhase) * math.pi / 180);
    final rectA = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 104, 66),
      const Radius.circular(20),
    );
    canvas.drawRRect(
      rectA,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9B8AF5), Color(0xFF5F3FDC), Color(0xFF4F25C4)],
          stops: [0, 0.55, 1],
        ).createShader(const Rect.fromLTWH(0, 0, 104, 66)),
    );
    // tail
    final tail = Path()
      ..moveTo(24, 66)
      ..lineTo(20, 82)
      ..lineTo(38, 70)
      ..close();
    canvas.drawPath(tail, Paint()..color = const Color(0xFF4F25C4));
    // three dots
    const dotOpacities = [0.92, 0.72, 0.52];
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(32 + i * 20.0, 33),
        5,
        Paint()..color = Colors.white.withValues(alpha: dotOpacities[i]),
      );
    }
    canvas.restore();

    // bubble B — floats 6.1 s in the opposite direction
    final bPhase = 0.5 - 0.5 * math.cos(2 * math.pi * (t * 5.2 / 6.1 + 0.35));
    canvas.save();
    canvas.translate(98, 76 + 7 * bPhase);
    canvas.rotate((4 - 6 * bPhase) * math.pi / 180);
    final rectB = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 86, 56),
      const Radius.circular(18),
    );
    canvas.drawRRect(rectB, Paint()..color = Colors.white);
    canvas.drawRRect(
      rectB,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE7E3F5),
    );
    final tailB = Path()
      ..moveTo(66, 56)
      ..lineTo(70, 69)
      ..lineTo(54, 58)
      ..close();
    canvas.drawPath(tailB, Paint()..color = Colors.white);
    canvas.drawLine(
      const Offset(66, 56),
      const Offset(70, 69),
      Paint()
        ..color = const Color(0xFFE7E3F5)
        ..strokeWidth = 1,
    );
    // two placeholder lines
    for (var i = 0; i < 2; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(14, 18 + i * 14.0, i == 0 ? 54 : 34, 7),
          const Radius.circular(3.5),
        ),
        Paint()..color = const Color(0xFFEDE9F9),
      );
    }
    canvas.restore();

    // three sparks (3.4 s, staggered)
    const sparks = [
      (Offset(176, 40), 4.0),
      (Offset(34, 140), 3.0),
      (Offset(150, 22), 2.6),
    ];
    for (var i = 0; i < sparks.length; i++) {
      final phase = (t * 5.2 / 3.4 + i * 0.2) % 1.0;
      final wave = 0.5 - 0.5 * math.cos(2 * math.pi * phase);
      final (position, radius) = sparks[i];
      canvas.drawCircle(
        position,
        radius * (0.85 + 0.25 * wave),
        Paint()
          ..color = (i == 2 ? const Color(0xFFE1D9FC) : const Color(0xFFC7B6FF))
              .withValues(alpha: 0.25 + 0.75 * wave),
      );
    }
  }

  @override
  bool shouldRepaint(_EmptyArtPainter oldDelegate) => oldDelegate.t != t;
}
