import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../chat/application/chat_controller.dart';
import '../../media/data/cloudinary_uploader.dart';
import '../../media/domain/media_asset.dart';
import '../data/audio_recorder.dart';
import '../domain/force_audio_alert.dart';
import 'force_audio_providers.dart';

final _log = AppLogger('force_audio');

// ------------------------------------------------------------- composer state
enum ComposerStage {
  idle,
  denied,
  recording,
  recorded,
  uploading,
  sending,
  sent,
  failed,
}

class ForceAudioComposerState {
  const ForceAudioComposerState({
    this.stage = ComposerStage.idle,
    this.elapsedMs = 0,
    this.level = 0,
    this.path,
    this.sizeBytes = 0,
    this.progress = 0,
    this.error,
  });

  final ComposerStage stage;
  final int elapsedMs;
  final double level;
  final String? path;
  final int sizeBytes;
  final double progress;
  final String? error;

  bool get isRecording => stage == ComposerStage.recording;
  bool get canSend => stage == ComposerStage.recorded;
  bool get isBusy =>
      stage == ComposerStage.uploading || stage == ComposerStage.sending;
  int get secondsLeft => ForceAudioLimits.secondsLeft(elapsedMs);

  ForceAudioComposerState copyWith({
    ComposerStage? stage,
    int? elapsedMs,
    double? level,
    String? path,
    int? sizeBytes,
    double? progress,
    String? error,
    bool clearError = false,
  }) => ForceAudioComposerState(
    stage: stage ?? this.stage,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    level: level ?? this.level,
    path: path ?? this.path,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    progress: progress ?? this.progress,
    error: clearError ? null : (error ?? this.error),
  );
}

/// The §5 sender machine: idle → recording → recorded → uploading(real %) →
/// submitted. The 70 s cap is enforced by a 100 ms timer, not by the server
/// rejecting the upload after the fact.
class ForceAudioComposerController extends Notifier<ForceAudioComposerState> {
  ForceAudioComposerController(this.conversationId);

  final String conversationId;

  /// Injected in tests to avoid touching the microphone.
  static ForceAudioRecorder? debugRecorderOverride;
  static CloudinaryUploader? debugUploaderOverride;

  Timer? _ticker;
  StreamSubscription<double>? _levels;

  @override
  ForceAudioComposerState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _levels?.cancel();
    });
    return const ForceAudioComposerState();
  }

  ForceAudioRecorder get _recorder =>
      debugRecorderOverride ?? ref.read(forceAudioRecorderProvider);

  CloudinaryUploader get _uploader =>
      debugUploaderOverride ?? CloudinaryUploader();

  Future<void> start() async {
    if (state.isRecording) return;
    final granted = await _recorder.ensurePermission();
    if (!granted) {
      state = const ForceAudioComposerState(
        stage: ComposerStage.denied,
        error:
            'Microphone access is off. Pulse needs it to record a Force Audio — '
            'enable it in Android settings, then try again.',
      );
      return;
    }

    final dir = Directory.systemTemp;
    final path =
        '${dir.path}/pulse_fa_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(path);
    } on Object catch (e) {
      _log.error('record_start_failed', error: e);
      state = const ForceAudioComposerState(
        stage: ComposerStage.failed,
        error: 'Could not start recording. Close other audio apps and retry.',
      );
      return;
    }

    _log.info('record_start');
    state = ForceAudioComposerState(stage: ComposerStage.recording, path: path);
    _levels = _recorder.amplitude(const Duration(milliseconds: 120)).listen((
      level,
    ) {
      if (state.isRecording) state = state.copyWith(level: level);
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!state.isRecording) return;
      final elapsed = state.elapsedMs + 100;
      state = state.copyWith(elapsedMs: elapsed);
      if (ForceAudioLimits.reachedDurationCap(elapsed)) {
        // Hard stop at 70 s: the upload would be rejected anyway.
        _log.info('record_cap_reached', data: {'ms': elapsed});
        unawaited(stop());
      }
    });
  }

  /// Stops the recorder and moves to `recorded` (or discards a too-short take).
  Future<void> stop({bool discard = false}) async {
    if (!state.isRecording) return;
    _ticker?.cancel();
    await _levels?.cancel();
    _levels = null;

    final path = await _recorder.stop();
    final resolved = path ?? state.path;
    if (discard || resolved == null) {
      await _safeDelete(resolved);
      state = const ForceAudioComposerState();
      return;
    }

    final file = File(resolved);
    final size = file.existsSync() ? await file.length() : 0;
    if (ForceAudioLimits.isTooShort(state.elapsedMs) || size == 0) {
      await _safeDelete(resolved);
      state = const ForceAudioComposerState(
        stage: ComposerStage.idle,
        error: 'That was too short — hold for at least a second.',
      );
      return;
    }

    state = state.copyWith(
      stage: ComposerStage.recorded,
      path: resolved,
      sizeBytes: size,
      level: 0,
    );
  }

  Future<void> discard() async {
    _ticker?.cancel();
    if (state.isRecording) {
      await _recorder.stop();
    }
    await _safeDelete(state.path);
    state = const ForceAudioComposerState();
  }

  /// Uploads the recording, then sends the message **and** the alert that makes
  /// it a Force Audio. Both rows are required: the receiver resolves the alert
  /// id against the server before it will touch the audio.
  Future<void> send() async {
    final path = state.path;
    if (path == null || state.stage != ComposerStage.recorded) return;

    final size = state.sizeBytes;
    if (ForceAudioLimits.isTooLarge(size)) {
      state = state.copyWith(
        stage: ComposerStage.failed,
        error: 'That recording is larger than 10 MB.',
      );
      return;
    }

    state = state.copyWith(stage: ComposerStage.uploading, progress: 0);

    try {
      final file = File(path);
      final media = PickedMedia(
        path: path,
        fileName: file.uri.pathSegments.last,
        sizeBytes: size,
        // Audio is Cloudinary's `video` resource type: it stores the right
        // content-type, which raw does not.
        resourceType: MediaResourceType.video,
      );
      final asset = await _uploader.upload(
        media,
        onProgress: (p) => state = state.copyWith(progress: p),
      );

      state = state.copyWith(stage: ComposerStage.sending, progress: 1);

      final thread = ref.read(chatThreadProvider(conversationId).notifier);
      final sent = await thread.sendForceAudio(
        mediaUrl: asset.secureUrl,
        sizeBytes: asset.bytes,
        durationMs: state.elapsedMs,
      );

      final conversation = ref.read(conversationsProvider.notifier);
      await conversation.refresh();
      if (sent == null) {
        state = state.copyWith(
          stage: ComposerStage.failed,
          error: 'The message went out but the alert could not be created.',
        );
        return;
      }

      state = state.copyWith(stage: ComposerStage.sent);
      await _safeDelete(path);
      _log.info(
        'force_audio_sent',
        data: {'bytes': asset.bytes, 'ms': state.elapsedMs},
      );
    } on AppFailure catch (e) {
      state = state.copyWith(stage: ComposerStage.failed, error: e.userMessage);
    } finally {
      state = state.copyWith(progress: 0);
    }
  }

  Future<void> _safeDelete(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on Object {
      // A leftover temp file is harmless.
    }
  }
}

final forceAudioComposerProvider = NotifierProvider.autoDispose
    .family<ForceAudioComposerController, ForceAudioComposerState, String>(
      ForceAudioComposerController.new,
    );

// ------------------------------------------------------------- receiver state
/// One alert on the receiving side. Everything here is server-verified: the
/// alert row is fetched by id, the audio is downloaded with real progress to a
/// private file, played once, and only then marked `played`.
class ForceAudioPlaybackController extends Notifier<ForceAudioReceiveState> {
  ForceAudioPlaybackController(this.alertId);

  final String alertId;

  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerSub;

  @override
  ForceAudioReceiveState build() {
    ref.onDispose(() {
      _playerSub?.cancel();
      _player?.dispose();
    });
    return const ForceAudioReceiveState();
  }

  Future<void> play() async {
    if (state.isBusy) return;
    state = state.copyWith(stage: ForceAudioReceiveStage.checking, progress: 0);

    final store = ref.read(playedAlertStoreProvider);
    final repo = ref.read(forceAudioRepositoryProvider);

    try {
      if (await store.isPlayed(alertId)) {
        state = state.copyWith(stage: ForceAudioReceiveStage.played);
        return;
      }

      final alert = await repo.fetch(alertId);
      if (alert == null) {
        // Unknown id: an old push, a deleted alert, or someone else's alert.
        state = state.copyWith(
          stage: ForceAudioReceiveStage.unauthorized,
          message: 'This Force Audio is no longer available.',
        );
        return;
      }
      if (alert.isExpired) {
        state = state.copyWith(stage: ForceAudioReceiveStage.expired);
        return;
      }

      if (alert.state == ForceAudioState.created) {
        unawaited(repo.markDelivered(alert.id));
      }

      state = state.copyWith(stage: ForceAudioReceiveStage.downloading);
      final file = await ref
          .read(forceAudioDownloaderProvider)
          .download(
            alert,
            onProgress: (p) {
              if (state.stage == ForceAudioReceiveStage.downloading) {
                state = state.copyWith(progress: p);
              }
            },
          );

      state = state.copyWith(stage: ForceAudioReceiveStage.ready, progress: 1);

      final player = _player ??= AudioPlayer();
      await player.setFilePath(file.path);
      state = state.copyWith(stage: ForceAudioReceiveStage.playing);

      _playerSub?.cancel();
      _playerSub = player.playerStateStream.listen((ps) {
        if (ps.processingState == ProcessingState.completed) {
          unawaited(_finish(alert.id));
        }
      });
      await player.seek(Duration.zero);
      await player.play();
    } on AppFailure catch (e) {
      state = state.copyWith(
        stage: ForceAudioReceiveStage.failed,
        message: e.userMessage,
      );
    } on Object catch (e) {
      _log.error('force_audio_play_failed', error: e);
      state = state.copyWith(
        stage: ForceAudioReceiveStage.failed,
        message: 'Playback failed. Tap to retry.',
      );
    }
  }

  Future<void> _finish(String id) async {
    state = state.copyWith(stage: ForceAudioReceiveStage.played);
    await ref.read(playedAlertStoreProvider).markPlayed(id);
    unawaited(ref.read(forceAudioRepositoryProvider).markPlayed(id));
    _log.info('force_audio_played', data: {'id': id});
  }
}

final forceAudioPlaybackProvider = NotifierProvider.autoDispose
    .family<ForceAudioPlaybackController, ForceAudioReceiveState, String>(
      ForceAudioPlaybackController.new,
    );
