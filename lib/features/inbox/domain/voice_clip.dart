import 'dart:math' as math;

import '../../chat/domain/message.dart';
import 'inbox_motion.dart';

/// A voice note, as the bubble needs it: an id (playback key), a URL and a
/// length. Bars are derived from the id so they never shuffle between builds.
class VoiceClip {
  const VoiceClip({
    required this.id,
    required this.url,
    required this.duration,
  });

  final String id;
  final String? url;
  final Duration duration;

  static VoiceClip fromMessage(Message message) => VoiceClip(
    id: message.id,
    url: message.mediaUrl,
    duration: Duration(
      milliseconds: (message.durationMs ?? 0) <= 0 ? 1000 : message.durationMs!,
    ),
  );

  bool get canPlay => url != null && url!.isNotEmpty;

  /// 22 deterministic bars in 0.32..1 — a stable "waveform fingerprint" per clip.
  List<double> barHeights([int count = InboxMotion.waveformBars]) {
    final seed = id.codeUnits.fold<int>(
      17,
      (acc, c) => (acc * 31 + c) & 0x7fffffff,
    );
    final phase = (seed % 628) / 100;
    return List<double>.generate(count, (i) {
      final a = math.sin(i * 0.86 + phase);
      final b = math.sin(i * 0.31 + phase * 0.7);
      final c = math.sin(i * 1.7 + phase * 1.9);
      final value = 0.5 + 0.34 * a + 0.16 * b + 0.08 * c;
      return value.clamp(0.32, 1.0);
    }, growable: false);
  }

  /// `0:07` — used under the bars.
  static String formatMmSs(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
