import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/message.dart';
import '../../application/voice_playback_controller.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';
import '../../domain/voice_clip.dart';
import 'bubble_shell.dart';
import 'playback_ring.dart';
import 'voice_waveform.dart';

/// A voice note: play/pause, 22 bars that fill with the play head, a readable
/// duration and the speed chip.
///
/// Playback is exclusive — [VoicePlaybackController] owns one player, so tapping
/// this bubble while another one plays stops that one first. The bubble only
/// reads state; it never starts its own player.
class VoiceNoteBubble extends ConsumerWidget {
  const VoiceNoteBubble({
    super.key,
    required this.message,
    required this.mine,
    this.stackPrev = false,
    this.stackNext = false,
  });

  final Message message;
  final bool mine;
  final bool stackPrev;
  final bool stackNext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = VoiceClip.fromMessage(message);
    final (owns, playing, speed) = ref.watch(
      voicePlaybackProvider.select(
        (state) => (
          state.currentId == clip.id,
          state.currentId == clip.id && state.playing,
          state.speed,
        ),
      ),
    );
    final controller = ref.read(voicePlaybackProvider.notifier);
    final progress = controller.progress;
    final fg = mine ? Colors.white : AppColors.brand600;

    Future<void> onPlay() async {
      final ok = await controller.toggle(
        id: clip.id,
        url: clip.url,
        duration: clip.duration,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This voice note could not be played.')),
        );
      }
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (playing || owns)
          Positioned.fill(
            child: PlaybackRing(
              progress: progress,
              playing: playing,
              radius: InboxMotion.bubbleRadius,
            ),
          ),
        BubbleShell(
          mine: mine,
          playing: playing,
          stackPrev: stackPrev,
          stackNext: stackNext,
          padding: InboxMotion.audioBubblePadding,
          child: SizedBox(
            width: 196,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PlayButton(
                      playing: playing,
                      mine: mine,
                      onTap: clip.canPlay ? onPlay : null,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: VoiceWaveform(
                        bars: clip.barHeights(),
                        progress: progress,
                        color: fg,
                        playing: playing,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<PlaybackProgress>(
                        valueListenable: progress,
                        builder: (context, value, _) {
                          final label = owns && value.total > Duration.zero
                              ? '${VoiceClip.formatMmSs(value.position)} / '
                                    '${VoiceClip.formatMmSs(value.total)}'
                              : VoiceClip.formatMmSs(clip.duration);
                          return Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: fg.withValues(alpha: owns ? 1 : 0.8),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SpeedChip(
                      speed: speed,
                      mine: mine,
                      onTap: () => controller.cycleSpeed(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.mine,
    required this.onTap,
  });

  final bool playing;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = playing
        ? InboxPalette.cyan
        : mine
        ? Colors.white.withValues(alpha: 0.92)
        : AppColors.brand100;
    final foreground = playing
        ? InboxPalette.cyanInk
        : mine
        ? AppColors.brand600
        : AppColors.brand600;

    return Semantics(
      button: true,
      label: playing ? 'Pause voice note' : 'Play voice note',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: InboxMotion.spring,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            boxShadow: playing
                ? [
                    BoxShadow(
                      color: InboxPalette.cyan.withValues(alpha: 0.45),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 20,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.speed,
    required this.mine,
    required this.onTap,
  });

  final double speed;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = speed == speed.roundToDouble()
        ? '${speed.toInt()}×'
        : '${speed.toStringAsFixed(1)}×';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: mine
              ? Colors.white.withValues(alpha: 0.22)
              : InboxPalette.brandTint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            height: 1.3,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: mine ? Colors.white : AppColors.brand700,
          ),
        ),
      ),
    );
  }
}
