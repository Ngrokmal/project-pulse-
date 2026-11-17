import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../application/inbox_audio_level.dart';
import '../../domain/inbox_motion.dart';

/// The voiced hint — "send when done" — drawn letter by letter so every glyph
/// can ride the live level.
///
/// Two details make it read as typography instead of a wobbling blur:
///
/// * every glyph is painted on **one shared baseline**, so a "d" and a "y" never
///   jump against each other (the letters only move together, by the level),
/// * the lift is capped at 2.4 px and the canvas has head-room, so a letter can
///   never leave the pill.
///
/// It repaints from `repaint: level` — no widget rebuilds at 60 fps.
class VoiceHint extends StatelessWidget {
  const VoiceHint({
    super.key,
    required this.level,
    required this.text,
    required this.color,
    required this.meterColor,
    required this.paused,
    this.showMeter = true,
  });

  final InboxAudioLevel level;
  final String text;
  final Color color;
  final Color meterColor;
  final bool paused;
  final bool showMeter;

  static const double meterWidth = 11;
  static const double meterGap = 5;
  static const double verticalPad = 4;

  static TextStyle styleFor(Color color) =>
      InboxMotion.hintStyle.copyWith(color: color);

  static TextPainter _layoutGlyph(String glyph, TextStyle style) => TextPainter(
    text: TextSpan(text: glyph, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Natural width of the hint at rest.
  static double measure(String text, TextStyle style, {bool meter = true}) {
    var width = meter ? meterWidth + meterGap : 0.0;
    for (final code in text.codeUnits) {
      if (code == 0x20) {
        width += InboxMotion.hintSpace;
        continue;
      }
      width += _layoutGlyph(String.fromCharCode(code), style).width;
    }
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(color);
    final glyphs = <String?>[];
    final offsets = <double>[];
    var x = showMeter ? meterWidth + meterGap : 0.0;
    var ascent = 0.0;
    var descent = 0.0;

    for (final code in text.codeUnits) {
      if (code == 0x20) {
        glyphs.add(null);
        offsets.add(x);
        x += InboxMotion.hintSpace;
        continue;
      }
      final glyph = String.fromCharCode(code);
      final painter = _layoutGlyph(glyph, style);
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      ascent = math.max(ascent, baseline);
      descent = math.max(descent, painter.height - baseline);
      glyphs.add(glyph);
      offsets.add(x);
      x += painter.width;
    }

    final textHeight = ascent + descent;
    final height = math.max(textHeight, 12.0) + verticalPad * 2;

    return RepaintBoundary(
      child: CustomPaint(
        size: Size(x, height),
        painter: _HintPainter(
          level: level,
          paused: paused,
          glyphs: glyphs,
          offsets: offsets,
          style: style,
          meterColor: meterColor,
          showMeter: showMeter,
          ascent: ascent,
          textTop: verticalPad + (math.max(textHeight, 12.0) - textHeight) / 2,
        ),
      ),
    );
  }
}

typedef _GlyphKey = (int index, int alphaBucket);

class _HintPainter extends CustomPainter {
  _HintPainter({
    required this.level,
    required this.paused,
    required this.glyphs,
    required this.offsets,
    required this.style,
    required this.meterColor,
    required this.showMeter,
    required this.ascent,
    required this.textTop,
  }) : super(repaint: level);

  final InboxAudioLevel level;
  final bool paused;
  final List<String?> glyphs;
  final List<double> offsets;
  final TextStyle style;
  final Color meterColor;
  final bool showMeter;
  final double ascent;
  final double textTop;

  /// Alpha-bucketed glyph painters: at most 24 variants per letter, so the
  /// per-frame cost is painting, never shaping.
  final Map<_GlyphKey, TextPainter> _alphaCache = {};
  static const int _buckets = 24;

  TextPainter _glyphPainter(int index, double opacity) {
    final bucket = (opacity.clamp(0.0, 1.0) * _buckets).round();
    final key = (index, bucket);
    final cached = _alphaCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(
        text: glyphs[index] ?? '',
        style: style.copyWith(
          color: (style.color ?? const Color(0xFF4F25C4)).withValues(
            alpha: bucket / _buckets,
          ),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _alphaCache[key] = painter;
    return painter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lvl = paused ? 0.0 : level.value;
    if (showMeter) _paintMeter(canvas, size, lvl);

    if (glyphs.isEmpty) return;

    final cycle = level.time * 1000 / InboxMotion.hintWave.inMilliseconds;
    final stagger =
        InboxMotion.hintStagger.inMilliseconds /
        InboxMotion.hintWave.inMilliseconds;

    final glowSigma = InboxMotion.hintGlow(lvl);
    if (glowSigma > 0.3) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()
          ..color = Colors.white.withValues(
            alpha: InboxMotion.hintGlowAlpha(lvl).clamp(0.0, 0.7),
          )
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: glowSigma,
            sigmaY: glowSigma,
          ),
      );
      _paintGlyphs(canvas, lvl, cycle, stagger);
      canvas.restore();
    }

    _paintGlyphs(canvas, lvl, cycle, stagger);
  }

  void _paintMeter(Canvas canvas, Size size, double lvl) {
    final base = size.height / 2 + 6;
    final heights = [
      InboxMotion.meterFirst(lvl),
      InboxMotion.meterSecond(lvl),
      InboxMotion.meterThird(lvl),
    ];
    const opacities = [0.9, 0.75, 0.6];
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 3; i++) {
      paint.color = meterColor.withValues(alpha: opacities[i]);
      final barHeight = heights[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * 3.75, base - barHeight, 2, barHeight),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  void _paintGlyphs(Canvas canvas, double lvl, double cycle, double stagger) {
    for (var i = 0; i < glyphs.length; i++) {
      if (glyphs[i] == null) continue;

      final phase = (cycle + i * stagger) % 1.0;
      // 0 %,100 %: rest · 50 %: peak — the amp gates the whole effect.
      final amp = (1 - math.cos(2 * math.pi * phase)) / 2;
      final dy = InboxMotion.hintLift(lvl) * amp;
      final scale = 1 + 0.15 * lvl * amp;
      final opacity = InboxMotion.hintOpacity(lvl * amp);

      final painter = _glyphPainter(i, opacity);
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );

      canvas.save();
      // One baseline for every letter, then the shared lift.
      canvas.translate(offsets[i], textTop + ascent - baseline + dy);
      if (scale != 1) {
        canvas.translate(0, baseline * (1 - scale));
        canvas.scale(scale);
      }
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HintPainter oldDelegate) =>
      oldDelegate.paused != paused ||
      oldDelegate.glyphs != glyphs ||
      oldDelegate.style != style ||
      oldDelegate.meterColor != meterColor ||
      oldDelegate.showMeter != showMeter;
}
