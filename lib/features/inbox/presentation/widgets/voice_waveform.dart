import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/voice_playback_controller.dart';
import '../../domain/inbox_motion.dart';

/// The 22-bar waveform of a voice bubble.
///
/// Bars below the play head are solid, the rest sit at 42 % — the reference's
/// `.fill` clip-path. It repaints from [progress] directly (no widget rebuild),
/// and breathes with the `waveBreath` scale while the clip is playing.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    required this.bars,
    required this.progress,
    required this.color,
    required this.playing,
  });

  final List<double> bars;
  final ValueListenable<PlaybackProgress> progress;
  final Color color;
  final bool playing;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with TickerProviderStateMixin {
  AnimationController? _breath;

  @override
  void initState() {
    super.initState();
    if (widget.playing) _startBreath();
  }

  @override
  void didUpdateWidget(VoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && _breath == null) {
      _startBreath();
    } else if (!widget.playing && _breath != null) {
      _breath!.dispose();
      _breath = null;
    }
  }

  void _startBreath() {
    final controller = AnimationController(
      vsync: this,
      duration: InboxMotion.waveBreath,
    )..repeat(reverse: true);
    _breath = controller;
  }

  @override
  void dispose() {
    _breath?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _WavePainter(
      bars: widget.bars,
      progress: widget.progress,
      color: widget.color,
      breath: _breath,
    );
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(double.infinity, 26),
        painter: painter,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.bars,
    required this.progress,
    required this.color,
    required AnimationController? breath,
  }) : _breath = breath,
       super(repaint: Listenable.merge([progress, ?breath]));

  final List<double> bars;
  final ValueListenable<PlaybackProgress> progress;
  final Color color;
  final AnimationController? _breath;

  /// Bars breathe 1 → 1.12 (`waveBreath`), never more.
  double get _scaleY => _breath == null ? 1 : 1 + 0.12 * _breath!.value;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0) return;
    const gap = 2.0;
    final barCount = bars.length;
    final barWidth = ((size.width - gap * (barCount - 1)) / barCount).clamp(
      2.0,
      8.0,
    );
    final spacing = barCount > 1
        ? (size.width - barWidth) / (barCount - 1)
        : size.width;
    final radius = Radius.circular(barWidth / 2);
    final played = progress.value.fraction;
    final centerY = size.height / 2;
    final scaleY = _scaleY;

    final muted = Paint()..color = color.withValues(alpha: 0.42);
    final solid = Paint()..color = color;

    for (var i = 0; i < barCount; i++) {
      final height = (bars[i] * size.height * scaleY).clamp(4.0, size.height);
      final left = i * spacing;
      final rect = Rect.fromLTWH(left, centerY - height / 2, barWidth, height);
      // The head is between bar i and i+1; a partially played bar is rounded
      // off by drawing the muted bar first and the solid bar on top.
      final playedEdge = played * barCount;
      if (playedEdge >= i + 1) {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), solid);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), muted);
        if (playedEdge > i) {
          final fraction = playedEdge - i;
          canvas.save();
          canvas.clipRect(
            Rect.fromLTWH(
              rect.left,
              rect.top,
              rect.width * fraction,
              rect.height,
            ),
          );
          canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), solid);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.bars != bars ||
      oldDelegate.color != color ||
      oldDelegate.progress != progress;
}
