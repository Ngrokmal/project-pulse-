import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../application/inbox_audio_level.dart';
import '../../application/inbox_providers.dart';
import '../../application/voice_recording_controller.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';
import '../../domain/inbox_record_state.dart';
import 'inbox_pressable.dart';
import 'recorder_wave.dart';
import 'voice_hint.dart';

/// The recorder, rebuilt from the reference v3 geometry:
///
/// * 46 px tall, `padding: 0 47px 0 11px`, `overflow: hidden` — **nothing can
///   escape the pill**, the bin included: it is an absolute 32 px button at
///   `right: 7, top: 7`, inside the border radius,
/// * the elapsed clock, 22 live bars and the voiced hint share the row,
/// * one `Ticker` advances the single [InboxAudioLevel]; every visual in here
///   (bars, hint letters, meter, halo) repaints from it without rebuilding.
class RecordingPill extends ConsumerStatefulWidget {
  const RecordingPill({super.key, required this.onDiscard});

  final VoidCallback onDiscard;

  @override
  ConsumerState<RecordingPill> createState() => _RecordingPillState();
}

class _RecordingPillState extends ConsumerState<RecordingPill>
    with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: InboxMotion.recIn,
  );
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _entry.forward();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _entry.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.016
        : (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    final recording =
        ref.read(voiceRecordingProvider).stage == RecordStage.recording;
    if (!recording) return;
    // Clamp so a paused app or a dropped frame cannot jolt the wave.
    ref.read(inboxAudioLevelProvider).advance(dt.clamp(0.0, 0.05));
  }

  Future<void> _discard() async {
    if (_entry.isAnimating) return;
    await _entry.animateBack(
      0,
      duration: InboxMotion.recOut,
      curve: Curves.easeIn,
    );
    if (!mounted) return;
    widget.onDiscard();
  }

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(
      voiceRecordingProvider.select((state) => state.stage),
    );
    final seconds = ref.watch(
      voiceRecordingProvider.select((state) => state.elapsedMs ~/ 1000),
    );
    final level = ref.watch(inboxAudioLevelProvider);
    final paused = stage != RecordStage.recording;
    final hintText = paused ? 'paused · send' : 'send when done';
    final style = VoiceHint.styleFor(
      paused ? InboxPalette.muted : InboxPalette.brand700,
    );

    return AnimatedBuilder(
      animation: _entry,
      builder: (context, child) {
        final t = _entry.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RecorderHalo(
              level: level,
              paused: paused,
              radius: InboxMotion.composeHeight / 2,
            ),
          ),
          GestureDetector(
            // The pill itself swallows taps so the composer behind it can never
            // receive a stray gesture while recording.
            onTap: () {},
            child: Container(
              height: InboxMotion.composeHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: (paused ? InboxPalette.hairline : InboxPalette.danger)
                      .withValues(alpha: paused ? 1 : 0.22),
                ),
                boxShadow: InboxPalette.recorder,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: InboxMotion.recorderPaddingLeft,
                        right: InboxMotion.recorderPaddingRight,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final dotWidth = 9.0;
                          final timeWidth = 34.0;
                          final gaps = 6.0 * 4;
                          final hintNatural = VoiceHint.measure(
                            hintText,
                            style,
                          );
                          final available =
                              constraints.maxWidth -
                              dotWidth -
                              timeWidth -
                              gaps;
                          const minWave = 44.0;
                          final hintWidth = math.max(
                            0.0,
                            math.min(hintNatural, available - minWave),
                          );
                          final waveWidth = math.max(
                            minWave,
                            available - hintWidth,
                          );
                          return Row(
                            children: [
                              _RecDot(paused: paused),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: timeWidth,
                                child: Text(
                                  _mmss(seconds),
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    color: paused
                                        ? InboxPalette.brand600
                                        : InboxPalette.danger,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: waveWidth,
                                child: Opacity(
                                  opacity: paused ? 0.3 : 1,
                                  child: RecorderWave(
                                    level: level,
                                    paused: paused,
                                  ),
                                ),
                              ),
                              if (hintWidth > 0) ...[
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: hintWidth,
                                  child: ClipRect(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerRight,
                                      child: VoiceHint(
                                        level: level,
                                        text: hintText,
                                        color: paused
                                            ? InboxPalette.muted
                                            : InboxPalette.brand700,
                                        meterColor: paused
                                            ? InboxPalette.muted
                                            : InboxPalette.brand700,
                                        paused: paused,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    // The bin: absolutely placed inside the pill, never outside
                    // it — 32 px square at right 7 / top 7.
                    Positioned(
                      right: InboxMotion.trashInset,
                      top: InboxMotion.trashInset,
                      child: InboxPressable(
                        onTap: _discard,
                        pressedScale: 0.86,
                        semanticLabel: 'Discard recording',
                        child: Container(
                          width: InboxMotion.trashSize,
                          height: InboxMotion.trashSize,
                          decoration: BoxDecoration(
                            color: InboxPalette.dangerTint,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            size: 17,
                            color: InboxPalette.danger,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _mmss(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// `@keyframes recPulse`: the red dot breathes with a 6 px ring that fades out.
class _RecDot extends StatefulWidget {
  const _RecDot({required this.paused});

  final bool paused;

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.paused) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_RecDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.paused && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (widget.paused && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final color = widget.paused
            ? InboxPalette.muted.withValues(alpha: 0.55)
            : InboxPalette.danger;
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: widget.paused
                ? null
                : [
                    BoxShadow(
                      color: InboxPalette.danger.withValues(
                        alpha: 0.4 * (1 - t),
                      ),
                      blurRadius: 0,
                      spreadRadius: 6 * t,
                    ),
                  ],
          ),
        );
      },
    );
  }
}
