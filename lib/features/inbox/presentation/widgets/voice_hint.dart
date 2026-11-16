import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../application/inbox_audio_level.dart';
import '../../domain/inbox_motion.dart';

/// The voiced hint — "send when done" — drawn letter by letter so every glyph
/// can ride the live level.
///
/// One `CustomPainter` on `repaint: level`: the level changes 60 times a second
/// and **no widget rebuilds** because of it. The three-bar voice meter is part of
/// the same canvas, so both move in lockstep.
class VoiceHint extends StatelessWidget {
  const VoiceHint({
    super.key,
    required this.level,
    required this.text,
    required this.color,
    required this.meterColor,
    required this.paused,
  });

  final InboxAudioLevel level;
  final String text;
  final Color color;
  final Color meterColor;
  final bool paused;

  static const double meterWidth = 11;
  static const double meterGap = 5;
  static const double verticalPad = 5;

  static TextStyle styleFor(Color color) =>
      InboxMotion.hintStyle.copyWith(color: color);

  static TextPainter _layoutGlyph(String glyph, TextStyle style) => TextPainter(
    text: TextSpan(text: glyph, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  /// Natural width of the hint at rest: meter + gap + letters.
  static double measure(String text, TextStyle style) {
    var width = 0.0;
    for (final code in text.codeUnits) {
      if (code == 0x20) {
        width += InboxMotion.hintSpace;
        continue;
      }
      width += _layoutGlyph(String.fromCharCode(code), style).width;
    }
    return meterWidth + meterGap + width;
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(color);
    final glyphs = <String?>[];
    final offsets = <double>[];
    final metrics = <TextPainter?>[];
    var x = meterWidth + meterGap;
    var height = 0.0;

    for (final code in text.codeUnits) {
      if (code == 0x20) {
        glyphs.add(null);
        metrics.add(null);
        offsets.add(x);
        x += InboxMotion.hintSpace;
        continue;
      }
      final glyph = String.fromCharCode(code);
      final painter = _layoutGlyph(glyph, style);
      glyphs.add(glyph);
      metrics.add(painter);
      offsets.add(x);
      x += painter.width;
      height = math.max(height, painter.height);
    }

    return RepaintBoundary(
      child: CustomPaint(
        size: Size(x, height + verticalPad * 2),
        painter: _HintPainter(
          level: level,
          paused: paused,
          glyphs: glyphs,
          metrics: metrics,
          offsets: offsets,
          style: style,
          meterColor: meterColor,
          textHeight: height,
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
    required this.metrics,
    required this.offsets,
    required this.style,
    required this.meterColor,
    required this.textHeight,
  }) : super(repaint: level);

  final InboxAudioLevel level;
  final bool paused;
  final List<String?> glyphs;
  final List<TextPainter?> metrics;
  final List<double> offsets;
  final TextStyle style;
  final Color meterColor;
  final double textHeight;

  /// Alpha-bucketed glyph painters: at most 24 variants per letter, so the
  /// per-frame cost is painting, never shaping.
  final Map<_GlyphKey, TextPainter> _alphaCache = {};
  static const int _buckets = 24;

  TextPainter _glyphPainter(int index, double opacity) {
    final bucket = (opacity.clamp(0.0, 1.0) * _buckets).round();
    final key = (index, bucket);
    final cached = _alphaCache[key];
    if (cached != null) return cached;
    final glyph = glyphs[index] ?? '';
    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
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
    _paintMeter(canvas, size, lvl);

    if (glyphs.isEmpty) return;

    final cycle = level.time * 1000 / InboxMotion.hintWave.inMilliseconds;
    final stagger =
        InboxMotion.hintStagger.inMilliseconds /
        InboxMotion.hintWave.inMilliseconds;

    // ---- the glow: one blurred pass, only while there is a voice.
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
    final base = size.height - VoiceHint.verticalPad - 1;
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
      final metric = metrics[i];
      if (metric == null) continue;

      final phase = (cycle + i * stagger) % 1.0;
      // 0 %,100 %: rest · 50 %: peak — the amp gates the whole effect.
      final amp = (1 - math.cos(2 * math.pi * phase)) / 2;
      final dy = InboxMotion.hintLift(lvl) * amp;
      final scale = 1 + 0.15 * lvl * amp;
      final opacity = InboxMotion.hintOpacity(lvl * amp);

      canvas.save();
      canvas.translate(
        offsets[i],
        VoiceHint.verticalPad + (textHeight - metric.height) + dy,
      );
      canvas.scale(scale);
      _glyphPainter(i, opacity).paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_HintPainter oldDelegate) =>
      oldDelegate.paused != paused ||
      oldDelegate.glyphs != glyphs ||
      oldDelegate.style != style ||
      oldDelegate.meterColor != meterColor;
}
