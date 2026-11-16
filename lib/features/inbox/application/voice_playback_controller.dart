import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/logging/app_logger.dart';

final _log = AppLogger('inbox.playback');

/// Position of whatever is playing, 0..1 for the progress arc.
///
/// This lives in a [ValueNotifier] on purpose: it changes 60 times a second and
/// must never rebuild the timeline. Only `CustomPainter`s and the duration label
/// listen to it.
@immutable
class PlaybackProgress {
  const PlaybackProgress({
    this.position = Duration.zero,
    this.total = Duration.zero,
  });

  final Duration position;
  final Duration total;

  double get fraction {
    final totalMs = total.inMilliseconds;
    if (totalMs <= 0) return 0;
    return (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackProgress &&
      other.position == position &&
      other.total == total;

  @override
  int get hashCode => Object.hash(position, total);
}

/// Which clip the (single) player currently owns.
@immutable
class VoicePlaybackState {
  const VoicePlaybackState({
    this.currentId,
    this.playing = false,
    this.speed = 1,
  });

  final String? currentId;
  final bool playing;
  final double speed;

  bool isPlaying(String id) => currentId == id && playing;
  bool owns(String id) => currentId == id;
  bool get isIdle => currentId == null;

  VoicePlaybackState copyWith({
    String? currentId,
    bool? playing,
    double? speed,
    bool clearCurrent = false,
  }) => VoicePlaybackState(
    currentId: clearCurrent ? null : (currentId ?? this.currentId),
    playing: clearCurrent ? false : (playing ?? this.playing),
    speed: speed ?? this.speed,
  );

  @override
  bool operator ==(Object other) =>
      other is VoicePlaybackState &&
      other.currentId == currentId &&
      other.playing == playing &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(currentId, playing, speed);
}

/// The global, exclusive audio coordinator for the inbox.
///
/// One player, one owner. Starting a clip **stops whatever was playing** — that
/// is not a courtesy, it is the contract: [toggle] always tears the previous
/// clip down before a new id can take over, so two voice notes can never talk
/// over each other.
class VoicePlaybackController extends Notifier<VoicePlaybackState> {
  static const List<double> speeds = [1, 1.5, 2];

  final ValueNotifier<PlaybackProgress> progress = ValueNotifier(
    const PlaybackProgress(),
  );

  AudioPlayer? _player;
  Timer? _ticker;
  Duration _total = Duration.zero;

  @override
  VoicePlaybackState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      progress.dispose();
      _player?.dispose();
      _player = null;
    });
    return const VoicePlaybackState();
  }

  AudioPlayer get _audio => _player ??= AudioPlayer();

  /// Plays [url] for message [id], or pauses it when it already owns the player.
  /// Returns false when the audio could not start (bad URL, codec, network).
  Future<bool> toggle({
    required String id,
    required String? url,
    required Duration duration,
  }) async {
    if (url == null || url.isEmpty) return false;

    if (state.currentId == id) {
      if (state.playing) {
        await _audio.pause();
        _ticker?.cancel();
        state = state.copyWith(playing: false);
        return true;
      }
      if (progress.value.fraction >= 0.999) {
        await _audio.seek(Duration.zero);
        progress.value = PlaybackProgress(total: _total);
      }
      unawaited(_audio.play());
      _startTicker();
      state = state.copyWith(playing: true);
      return true;
    }

    // Exclusivity: everything that was playing stops here, before the new clip
    // is even loaded.
    await stop();

    try {
      _total = duration;
      progress.value = PlaybackProgress(total: _total);
      state = VoicePlaybackState(
        currentId: id,
        playing: false,
        speed: state.speed,
      );
      await _audio.setUrl(url);
      await _audio.setSpeed(state.speed);
      unawaited(_audio.play());
      _startTicker();
      state = state.copyWith(playing: true);
      return true;
    } on Object catch (error) {
      _log.warning('playback_failed', data: {'error': '$error'});
      await stop();
      return false;
    }
  }

  /// Cycles 1× → 1.5× → 2× for the clip that owns the player.
  Future<void> cycleSpeed() async {
    final index = speeds.indexOf(state.speed);
    final next = speeds[(index + 1) % speeds.length];
    state = state.copyWith(speed: next);
    final player = _player;
    if (player != null && state.currentId != null) {
      try {
        await player.setSpeed(next);
      } on Object catch (_) {
        // Speed is cosmetic; a failure must not stop the audio.
      }
    }
  }

  /// Stops playback and gives the player back. Safe to call at any time.
  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    _total = Duration.zero;
    progress.value = const PlaybackProgress();
    final player = _player;
    if (player != null) {
      try {
        await player.stop();
      } on Object catch (_) {
        // Nothing to do: the player is being reset anyway.
      }
    }
    if (state != const VoicePlaybackState()) {
      state = VoicePlaybackState(speed: state.speed);
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final player = _player;
      if (player == null) return;
      final position = player.position;
      final clamped = position > _total ? _total : position;
      progress.value = PlaybackProgress(position: clamped, total: _total);
      if (_total > Duration.zero && position >= _total) {
        unawaited(_finish());
      }
    });
  }

  Future<void> _finish() async {
    _ticker?.cancel();
    _ticker = null;
    try {
      await _audio.pause();
      await _audio.seek(Duration.zero);
    } on Object catch (_) {
      // Ignore: the visual state is what the user sees next.
    }
    progress.value = PlaybackProgress(total: _total);
    state = state.copyWith(playing: false);
  }
}

final voicePlaybackProvider =
    NotifierProvider<VoicePlaybackController, VoicePlaybackState>(
      VoicePlaybackController.new,
    );
