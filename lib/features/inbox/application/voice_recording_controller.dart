import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../chat/application/chat_controller.dart';
import '../../chat/domain/message.dart';
import '../../media/domain/media_asset.dart';
import '../data/voice_recorder.dart';
import '../domain/inbox_record_state.dart';
import 'inbox_providers.dart';

final _log = AppLogger('inbox.record');

/// The record model of the reference, as a state machine:
///
/// tap the mic → `recording` (keeps rolling, releasing does nothing)
/// tap again → `paused` → tap again → `recording`
/// the bin → discard, the send button → upload + `MessageKind.audio`.
class VoiceRecordingController extends Notifier<InboxRecordState> {
  /// A hard ceiling so a forgotten recording cannot grow forever.
  static const Duration maxTake = Duration(minutes: 3);

  Timer? _elapsed;
  StreamSubscription<double>? _levels;
  final Stopwatch _watch = Stopwatch();

  @override
  InboxRecordState build() {
    ref.onDispose(() {
      _elapsed?.cancel();
      _levels?.cancel();
      _watch.stop();
    });
    return InboxRecordState.idle;
  }

  VoiceRecorder get _recorder => ref.read(voiceRecorderProvider);

  /// Starts a take. Returns a human-readable reason when it could not start.
  Future<String?> start() async {
    if (state.stage != RecordStage.idle) return null;

    final granted = await _recorder.ensurePermission();
    if (!granted) {
      return 'Microphone access is off. Pulse needs it to record a voice note — '
          'enable it in Android settings, then try again.';
    }

    final path =
        '${Directory.systemTemp.path}/pulse_note_'
        '${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(path);
    } on Object catch (error) {
      _log.error('record_start_failed', error: error);
      return 'Could not start recording. Close other audio apps and retry.';
    }

    _watch
      ..reset()
      ..start();
    state = InboxRecordState(stage: RecordStage.recording, path: path);
    ref.read(inboxAudioLevelProvider).reset();

    _levels = _recorder.levels().listen((level) {
      ref.read(inboxAudioLevelProvider).setTarget(level);
    });

    _elapsed = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (state.stage != RecordStage.recording) return;
      final elapsed = _watch.elapsedMilliseconds;
      state = state.copyWith(elapsedMs: elapsed);
      if (elapsed >= maxTake.inMilliseconds) {
        unawaited(pause());
      }
    });
    return null;
  }

  /// Pauses the recorder — the take is kept, the mic becomes a resume button.
  Future<void> pause() async {
    if (state.stage != RecordStage.recording) return;
    _watch.stop();
    try {
      await _recorder.pause();
    } on Object catch (error) {
      _log.warning('record_pause_failed', data: {'error': '$error'});
    }
    ref.read(inboxAudioLevelProvider).silence();
    state = state.copyWith(
      stage: RecordStage.paused,
      elapsedMs: _watch.elapsedMilliseconds,
    );
  }

  Future<void> resume() async {
    if (state.stage != RecordStage.paused) return;
    try {
      await _recorder.resume();
    } on Object catch (error) {
      _log.warning('record_resume_failed', data: {'error': '$error'});
      return;
    }
    _watch.start();
    state = state.copyWith(stage: RecordStage.recording);
  }

  /// Discards the take and deletes the file. Never sends anything.
  Future<void> discard() async {
    if (state.stage == RecordStage.idle) return;
    _elapsed?.cancel();
    _elapsed = null;
    await _levels?.cancel();
    _levels = null;
    _watch.stop();
    final path = state.path;
    state = InboxRecordState.idle;
    ref.read(inboxAudioLevelProvider).reset();
    try {
      final stopped = await _recorder.stop();
      await VoiceRecorder.deleteTake(stopped ?? path);
    } on Object catch (_) {
      await VoiceRecorder.deleteTake(path);
    }
  }

  /// Uploads the take and sends it as a real audio message.
  /// Returns null on success, or the message to show the user.
  Future<String?> send({required String conversationId}) async {
    if (state.stage == RecordStage.idle) return null;
    final take = state;
    final path = take.path;
    if (path == null) {
      await discard();
      return 'Nothing to send.';
    }

    _elapsed?.cancel();
    _elapsed = null;
    await _levels?.cancel();
    _levels = null;
    _watch.stop();
    ref.read(inboxAudioLevelProvider).silence();

    final durationMs = take.elapsedMs;
    state = state.copyWith(stage: RecordStage.sending);

    try {
      final stopped = await _recorder.stop();
      final file = File(stopped ?? path);
      final bytes = file.existsSync() ? await file.length() : 0;
      if (bytes < 2048 || durationMs < 400) {
        await VoiceRecorder.deleteTake(stopped ?? path);
        state = InboxRecordState.idle;
        return 'That recording was too short to send.';
      }

      final media = PickedMedia(
        path: file.path,
        fileName: file.uri.pathSegments.last,
        sizeBytes: bytes,
        resourceType: MediaResourceType.raw,
      );
      await ref
          .read(chatThreadProvider(conversationId).notifier)
          .sendMedia(
            media: media,
            kind: MessageKind.audio,
            durationMs: durationMs,
          );
      await VoiceRecorder.deleteTake(file.path);
      state = InboxRecordState.idle;
      ref.read(inboxAudioLevelProvider).reset();
      return null;
    } on AppFailure catch (failure) {
      // Keep the take: a failed upload must be retryable, not lost.
      state = InboxRecordState(
        stage: RecordStage.paused,
        elapsedMs: durationMs,
        path: path,
        sizeBytes: take.sizeBytes,
      );
      return failure.userMessage;
    } on Object catch (error) {
      _log.error('voice_send_failed', error: error);
      state = InboxRecordState(
        stage: RecordStage.paused,
        elapsedMs: durationMs,
        path: path,
        sizeBytes: take.sizeBytes,
      );
      return 'Could not send the voice note. Check your connection and retry.';
    }
  }
}

final voiceRecordingProvider =
    NotifierProvider<VoiceRecordingController, InboxRecordState>(
      VoiceRecordingController.new,
    );
