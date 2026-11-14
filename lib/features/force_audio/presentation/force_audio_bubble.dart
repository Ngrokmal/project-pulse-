import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/force_audio_controllers.dart';
import '../application/force_audio_providers.dart';
import '../domain/force_audio_alert.dart';

/// The Force Audio bubble.
///
/// Receiver flow (§5), all server-verified:
///   verify the alert id → "Checking for new messages" → download with real
///   percentage → play once → mark played.
/// Nothing here trusts a URL that came from a push.
class ForceAudioBubble extends ConsumerStatefulWidget {
  const ForceAudioBubble({
    super.key,
    required this.messageId,
    required this.mine,
    this.durationMs,
  });

  final String messageId;
  final bool mine;
  final int? durationMs;

  @override
  ConsumerState<ForceAudioBubble> createState() => _ForceAudioBubbleState();
}

class _ForceAudioBubbleState extends ConsumerState<ForceAudioBubble> {
  static final _log = AppLogger('force_audio.bubble');

  String? _alertId;
  bool _resolving = false;
  String? _resolveError;

  Future<void> _resolveAndPlay() async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _resolveError = null;
    });
    try {
      if (_alertId == null) {
        final alert = await ref
            .read(forceAudioRepositoryProvider)
            .fetchByMessage(widget.messageId);
        if (alert == null) {
          // The message exists but the alert cannot be resolved: an old row, or
          // someone else's alert. Say so instead of offering a dead play button.
          setState(() {
            _resolveError = 'This Force Audio is unavailable.';
            _resolving = false;
          });
          return;
        }
        _alertId = alert.id;
      }
      await ref.read(forceAudioPlaybackProvider(_alertId!).notifier).play();
    } on AppFailure catch (e) {
      _log.error('bubble_resolve_failed');
      setState(() => _resolveError = e.userMessage);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine ? AppColors.onPrimary : AppColors.brand700;
    final soft = widget.mine
        ? AppColors.onPrimary.withValues(alpha: 0.18)
        : AppColors.brand100;

    final alertId = _alertId;
    final playback = alertId == null
        ? const ForceAudioReceiveState()
        : ref.watch(forceAudioPlaybackProvider(alertId));

    final stage = playback.stage;
    final busy =
        _resolving ||
        stage == ForceAudioReceiveStage.checking ||
        stage == ForceAudioReceiveStage.downloading;
    final label = switch (stage) {
      ForceAudioReceiveStage.checking => 'Checking for new messages…',
      ForceAudioReceiveStage.downloading =>
        'Downloading ${(playback.progress * 100).round()}%',
      ForceAudioReceiveStage.ready => 'Ready',
      ForceAudioReceiveStage.playing => 'Playing…',
      ForceAudioReceiveStage.played => 'Played',
      ForceAudioReceiveStage.expired => 'Expired',
      ForceAudioReceiveStage.unauthorized => 'Unavailable',
      ForceAudioReceiveStage.failed => playback.message ?? 'Tap to retry',
      ForceAudioReceiveStage.idle =>
        _resolveError ??
            (widget.mine
                ? 'Force Audio · ${ForceAudioLimits.format(widget.durationMs ?? 0)}'
                : 'Tap to play'),
    };

    final progress = stage == ForceAudioReceiveStage.downloading
        ? playback.progress
        : null;
    final canTap =
        !busy &&
        stage != ForceAudioReceiveStage.playing &&
        stage != ForceAudioReceiveStage.played &&
        stage != ForceAudioReceiveStage.expired &&
        stage != ForceAudioReceiveStage.unauthorized;

    return InkWell(
      onTap: canTap ? _resolveAndPlay : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 2.2,
                          color: fg,
                        ),
                      )
                    : Icon(
                        stage == ForceAudioReceiveStage.playing
                            ? Icons.graphic_eq_rounded
                            : stage == ForceAudioReceiveStage.played
                            ? Icons.check_rounded
                            : stage == ForceAudioReceiveStage.expired ||
                                  stage == ForceAudioReceiveStage.unauthorized
                            ? Icons.block_rounded
                            : Icons.play_arrow_rounded,
                        color: fg,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.mine ? 'Force Audio sent' : 'Force Audio',
                      style: AppTypography.titleMedium.copyWith(
                        color: fg,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      label,
                      style: AppTypography.caption.copyWith(
                        fontSize: 11,
                        color: widget.mine
                            ? AppColors.onPrimary.withValues(alpha: 0.8)
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: soft,
                valueColor: AlwaysStoppedAnimation(fg),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
