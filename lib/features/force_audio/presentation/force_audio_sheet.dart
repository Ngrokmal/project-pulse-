import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../application/force_audio_controllers.dart';
import '../domain/force_audio_alert.dart';

/// Opens the Force Audio recorder as a modal sheet. Returns when the sheet is
/// closed; the sheet disposes the recorder either way.
Future<void> showForceAudioSheet(
  BuildContext context, {
  required String conversationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ForceAudioSheet(conversationId: conversationId),
  );
}

class ForceAudioSheet extends ConsumerWidget {
  const ForceAudioSheet({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(forceAudioComposerProvider(conversationId));
    final controller = ref.read(
      forceAudioComposerProvider(conversationId).notifier,
    );

    // Close as soon as the alert is on the server; the chat list already shows
    // the new message by then.
    ref.listen(forceAudioComposerProvider(conversationId), (previous, next) {
      if (next.stage == ComposerStage.sent &&
          previous?.stage != ComposerStage.sent) {
        Navigator.of(context).maybePop();
      }
    });

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand100,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  color: AppColors.brand700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Force Audio', style: AppTypography.titleMedium),
                    Text(
                      'Plays out loud on their phone',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Body(
            conversationId: conversationId,
            state: state,
            controller: controller,
          ),
          const SizedBox(height: 12),
          Text(
            'Up to 1:10 · 10 MB max',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    required this.conversationId,
    required this.state,
    required this.controller,
  });

  final String conversationId;
  final ForceAudioComposerState state;
  final ForceAudioComposerController controller;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  AudioPlayer? _player;
  bool _previewing = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePreview() async {
    final path = widget.state.path;
    if (path == null) return;
    final player = _player ??= AudioPlayer();
    if (_previewing) {
      await player.pause();
      setState(() => _previewing = false);
      return;
    }
    await player.setFilePath(path);
    await player.seek(Duration.zero);
    setState(() => _previewing = true);
    await player.play();
    player.playerStateStream.listen((ps) {
      if (ps.processingState == ProcessingState.completed && mounted) {
        setState(() => _previewing = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = widget.controller;

    switch (state.stage) {
      case ComposerStage.denied:
      case ComposerStage.failed:
        return Column(
          children: [
            PulseInlineNotice(
              message: state.error ?? 'Something went wrong.',
              tone: NoticeTone.warning,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => controller.discard(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => controller.start(),
                    child: const Text('Try again'),
                  ),
                ),
              ],
            ),
          ],
        );

      case ComposerStage.uploading:
      case ComposerStage.sending:
        final pct = (state.progress * 100).clamp(0, 100).toStringAsFixed(0);
        return Column(
          children: [
            Text(
              state.stage == ComposerStage.uploading
                  ? 'Uploading — $pct%'
                  : 'Sending…',
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: state.stage == ComposerStage.uploading
                    ? state.progress
                    : null,
                minHeight: 6,
                backgroundColor: AppColors.brand100,
                valueColor: const AlwaysStoppedAnimation(AppColors.brand600),
              ),
            ),
          ],
        );

      case ComposerStage.recording:
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ForceAudioLimits.format(state.elapsedMs),
                  style: AppTypography.displaySmall.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Text('/ 1:10', style: AppTypography.caption),
              ],
            ),
            const SizedBox(height: 14),
            _LevelMeter(level: state.level),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => controller.stop(discard: true),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => controller.stop(),
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ],
        );

      case ComposerStage.recorded:
        return Column(
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: _togglePreview,
                  icon: Icon(
                    _previewing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recorded ${ForceAudioLimits.format(state.elapsedMs)}',
                        style: AppTypography.titleMedium,
                      ),
                      Text(
                        '${(state.sizeBytes / 1024).toStringAsFixed(0)} KB · '
                        '${state.secondsLeft}s spare',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await _player?.stop();
                    setState(() => _previewing = false);
                    await controller.discard();
                  },
                  child: const Text('Redo'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: controller.send,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Send Force Audio'),
              ),
            ),
          ],
        );

      case ComposerStage.idle:
      case ComposerStage.sent:
        return Column(
          children: [
            GestureDetector(
              onTap: controller.start,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.brand600,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand600.withValues(alpha: 0.28),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text('Tap to record', style: AppTypography.caption),
            if (state.error != null) ...[
              const SizedBox(height: 10),
              PulseInlineNotice(
                message: state.error!,
                tone: NoticeTone.warning,
              ),
            ],
          ],
        );
    }
  }
}

/// Live input level — the bars move with the microphone, so a muted mic is
/// visible before the user sends a silent recording.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(24, (i) {
          final distance = (i - 11.5).abs() / 11.5;
          final weight = 1 - distance * 0.65;
          final h = 8 + (level * weight * 36);
          final active = (level * 24) > (i - 4);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 110),
              width: 4,
              height: h.clamp(6.0, 44.0),
              decoration: BoxDecoration(
                color: active ? AppColors.brand600 : AppColors.brand100,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}
