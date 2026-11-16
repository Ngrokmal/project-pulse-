import 'dart:async';
import 'dart:io';

import 'package:record/record.dart';

import '../../../core/logging/app_logger.dart';

/// Thin, honest wrapper over `record` — the same microphone path the Force Audio
/// recorder uses, exposed with a level stream for the voiced UI.
///
/// Nothing here simulates sound: when the microphone is unavailable the panel
/// says so instead of animating a fake waveform.
class VoiceRecorder {
  VoiceRecorder({AudioRecorder? recorder, AppLogger? logger})
    : _recorder = recorder ?? AudioRecorder(),
      _log = logger ?? AppLogger('inbox.recorder');

  /// 64 kbps mono AAC in an m4a container: small, and plays on every Android
  /// build this app ships to.
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

  Future<void> pause() => _recorder.pause();

  Future<void> resume() => _recorder.resume();

  Future<String?> stop() => _recorder.stop();

  /// 0..1 level, ~9 samples per second. Enough for the smoother to work from
  /// without waking the UI up more than the microphone does anyway.
  Stream<double> levels({
    Duration interval = const Duration(milliseconds: 110),
  }) => _recorder
      .onAmplitudeChanged(interval)
      .map((amplitude) => normalise(amplitude.current))
      .handleError((Object error) => _log.warning('level_stream_error'));

  Future<void> dispose() => _recorder.dispose();

  /// dBFS (−60..0) → 0..1, the same curve as the reference's `sqrt` RMS.
  static double normalise(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite) return 0;
    const floor = -45.0;
    final clamped = dbfs.clamp(floor, 0.0);
    return ((clamped - floor) / -floor).clamp(0.0, 1.0);
  }

  /// Deletes a discarded take so a rolled-back recording never leaks a file.
  static Future<void> deleteTake(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A leftover temp file is harmless; never let cleanup break the UI.
    }
  }
}
