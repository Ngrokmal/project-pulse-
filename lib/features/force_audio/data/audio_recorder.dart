import 'dart:async';

import 'package:record/record.dart';

import '../../../core/logging/app_logger.dart';

/// Thin wrapper over `record` (real microphone, no simulation).
///
/// Android needs `RECORD_AUDIO`; `hasPermission(request: true)` shows the system
/// prompt the first time, and returns false if the user refuses — the UI shows a
/// real explanation instead of pretending to record.
class ForceAudioRecorder {
  ForceAudioRecorder({AudioRecorder? recorder, AppLogger? logger})
    : _recorder = recorder ?? AudioRecorder(),
      _log = logger ?? AppLogger('force_audio');

  /// Opus/AAC in an MP4 container plays everywhere on Android and is small:
  /// 64 kbps × 70 s ≈ 560 KB, far below the 10 MiB ceiling.
  static const RecordConfig config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
  );

  final AudioRecorder _recorder;
  final AppLogger _log;

  Future<bool> ensurePermission() async {
    final granted = await _recorder.hasPermission();
    _log.info('mic_permission', data: {'granted': granted});
    return granted;
  }

  Future<void> start(String path) => _recorder.start(config, path: path);

  /// Returns the path of the file that was written, or null if nothing was.
  Future<String?> stop() => _recorder.stop();

  Stream<double> amplitude(Duration interval) =>
      _recorder.onAmplitudeChanged(interval).map((a) => _normalise(a.current));

  Future<void> dispose() => _recorder.dispose();

  /// dBFS (-60..0) to 0..1 so the meters are visible without a scale bar.
  static double _normalise(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite) return 0;
    const floor = -45.0;
    final clamped = dbfs.clamp(floor, 0.0);
    return ((clamped - floor) / -floor).clamp(0.0, 1.0);
  }
}
