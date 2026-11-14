import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/force_audio_controllers.dart';
import '../domain/force_audio_alert.dart';

/// The Force Audio takeover screen (§5, receiver side).
///
/// Opened from a notification tap (or the in-app banner). It never trusts the
/// push payload: it resolves the alert id against the server, shows the real
/// "Checking for new messages" state for as long as the download takes, then
/// plays the file once. A second open of the same alert says "Played" and does
/// not replay — the guard is persisted, not in-memory.
class ForceAudioScreen extends ConsumerStatefulWidget {
  const ForceAudioScreen({super.key, required this.alertId});

  final String alertId;

  @override
  ConsumerState<ForceAudioScreen> createState() => _ForceAudioScreenState();
}

class _ForceAudioScreenState extends ConsumerState<ForceAudioScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Autoplay once the first frame is up, so the "checking" state is visible
    // instead of the screen flashing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started || !mounted) return;
    _started = true;
    await ref.read(forceAudioPlaybackProvider(widget.alertId).notifier).play();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/app');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(forceAudioPlaybackProvider(widget.alertId));
    final stage = state.stage;

    final busy =
        stage == ForceAudioReceiveStage.checking ||
        stage == ForceAudioReceiveStage.downloading;
    final done =
        stage == ForceAudioReceiveStage.played ||
        stage == ForceAudioReceiveStage.expired ||
        stage == ForceAudioReceiveStage.unauthorized;
    final failed = stage == ForceAudioReceiveStage.failed;

    return Scaffold(
      backgroundColor: AppColors.navy900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenX,
            vertical: 18,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _close,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.onPrimary,
                    ),
                    tooltip: 'Close',
                  ),
                  const Spacer(),
                  Text(
                    'FORCE AUDIO',
                    style: AppTypography.micro.copyWith(
                      color: AppColors.onPrimary.withValues(alpha: 0.7),
                      letterSpacing: 2.2,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 44),
                ],
              ),
              const Spacer(),
              _Pulse(stage: stage, progress: state.progress),
              const SizedBox(height: 34),
              Text(
                _headline(stage),
                textAlign: TextAlign.center,
                style: AppTypography.displaySmall.copyWith(
                  color: AppColors.onPrimary,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _detail(stage, state),
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.onPrimary.withValues(alpha: 0.72),
                ),
              ),
              if (stage == ForceAudioReceiveStage.downloading) ...[
                const SizedBox(height: 22),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 6,
                    backgroundColor: AppColors.onPrimary.withValues(
                      alpha: 0.14,
                    ),
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.brand300,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(state.progress * 100).round()}%',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onPrimary.withValues(alpha: 0.65),
                  ),
                ),
              ],
              const Spacer(),
              if (busy)
                Text(
                  'Keep this screen open — the audio is being prepared.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.onPrimary.withValues(alpha: 0.5),
                  ),
                )
              else if (failed)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      _started = false;
                      _start();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
                  ),
                )
              else if (done)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _close,
                    child: const Text('Close'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onPrimary,
                      side: BorderSide(
                        color: AppColors.onPrimary.withValues(alpha: 0.4),
                      ),
                    ),
                    onPressed: _close,
                    child: const Text('Done'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Copy is deliberately literal: no fake progress, no invented percentages.
  static String _headline(ForceAudioReceiveStage stage) => switch (stage) {
    ForceAudioReceiveStage.idle => 'Loading…',
    ForceAudioReceiveStage.checking => 'Checking for new messages',
    ForceAudioReceiveStage.downloading => 'Checking for new messages',
    ForceAudioReceiveStage.ready => 'Ready',
    ForceAudioReceiveStage.playing => 'Playing Force Audio',
    ForceAudioReceiveStage.played => 'Played',
    ForceAudioReceiveStage.expired => 'This alert expired',
    ForceAudioReceiveStage.unauthorized => 'This alert is not available',
    ForceAudioReceiveStage.failed => 'Playback failed',
  };

  static String _detail(
    ForceAudioReceiveStage stage,
    ForceAudioReceiveState s,
  ) => switch (stage) {
    ForceAudioReceiveStage.checking => 'Verifying this alert with the server.',
    ForceAudioReceiveStage.downloading => 'Downloading the audio…',
    ForceAudioReceiveStage.playing => 'It plays once, then disappears.',
    ForceAudioReceiveStage.played => 'You have already heard this one.',
    ForceAudioReceiveStage.expired =>
      'Force Audio alerts only live for 24 hours.',
    ForceAudioReceiveStage.unauthorized =>
      'It may have been deleted, or it was not sent to you.',
    ForceAudioReceiveStage.failed => s.message ?? 'Tap Try again.',
    _ => '',
  };
}

/// Visual: a breathing ring while working, bars while playing, a tick when done.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.stage, required this.progress});

  final ForceAudioReceiveStage stage;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final working =
        stage == ForceAudioReceiveStage.checking ||
        stage == ForceAudioReceiveStage.downloading;
    return SizedBox(
      width: 190,
      height: 190,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 190,
              height: 190,
              child: CircularProgressIndicator(
                value: stage == ForceAudioReceiveStage.downloading
                    ? null
                    : null,
                strokeWidth: 3,
                backgroundColor: AppColors.onPrimary.withValues(alpha: 0.10),
                valueColor: const AlwaysStoppedAnimation(AppColors.brand400),
              ),
            ),
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(
                working
                    ? Icons.cloud_download_outlined
                    : stage == ForceAudioReceiveStage.playing
                    ? Icons.graphic_eq_rounded
                    : stage == ForceAudioReceiveStage.played
                    ? Icons.check_rounded
                    : Icons.error_outline_rounded,
                color: AppColors.onPrimary,
                size: 46,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
