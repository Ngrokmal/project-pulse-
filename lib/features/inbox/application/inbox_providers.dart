import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/voice_recorder.dart';
import 'inbox_audio_level.dart';

/// Dependency wiring for the inbox. One recorder, one level, so the whole screen
/// reads the same microphone.
final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = VoiceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});

/// The single live level (the reference's `--lvl`). Screen-scoped, disposed with
/// the screen.
final inboxAudioLevelProvider = Provider<InboxAudioLevel>((ref) {
  final level = InboxAudioLevel();
  ref.onDispose(level.dispose);
  return level;
});
