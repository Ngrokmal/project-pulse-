import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/message.dart';
import '../../application/inbox_providers.dart';
import '../../application/voice_recording_controller.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';
import '../../domain/inbox_record_state.dart';
import 'inbox_pressable.dart';
import 'recording_pill.dart';
import 'send_button.dart';

/// The composer: mic, attach, the 46 px field and send.
///
/// While recording the field and the attach button disappear and the recorder
/// pill takes the free space — the same swap the reference does, with a real
/// state machine behind it.
class ComposerBar extends ConsumerStatefulWidget {
  const ComposerBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSendText,
    required this.onSendVoice,
    required this.onPickPhoto,
    required this.onPickFile,
    required this.onTyping,
    required this.onToggleAttach,
    required this.attachOpen,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSendText;
  final Future<String?> Function() onSendVoice;
  final VoidCallback onPickPhoto;
  final VoidCallback onPickFile;
  final VoidCallback onTyping;
  final VoidCallback onToggleAttach;
  final bool attachOpen;

  @override
  ConsumerState<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends ConsumerState<ComposerBar> {
  bool _sendingText = false;

  Future<void> _startRecording() async {
    final error = await ref.read(voiceRecordingProvider.notifier).start();
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _send() async {
    final record = ref.read(voiceRecordingProvider);
    if (record.isBusy) return;
    if (record.stage != RecordStage.idle) {
      final error = await widget.onSendVoice();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    if (widget.controller.text.trim().isEmpty || _sendingText) return;
    setState(() => _sendingText = true);
    try {
      await widget.onSendText();
    } finally {
      if (mounted) setState(() => _sendingText = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = ref.watch(voiceRecordingProvider);
    final level = ref.watch(inboxAudioLevelProvider);
    final recording = record.stage != RecordStage.idle;
    final paused = record.stage == RecordStage.paused;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF4F2FB).withValues(alpha: 0),
            const Color(0xFFF4F2FB).withValues(alpha: 0.96),
          ],
          stops: const [0, 0.45],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _MicButton(
            paused: paused,
            recording: recording,
            onTap: () {
              if (record.isBusy) return;
              if (record.stage == RecordStage.idle) {
                _startRecording();
              } else if (record.stage == RecordStage.recording) {
                ref.read(voiceRecordingProvider.notifier).pause();
              } else {
                ref.read(voiceRecordingProvider.notifier).resume();
              }
            },
          ),
          const SizedBox(width: 8),
          if (!recording)
            InboxPressable(
              onTap: widget.onToggleAttach,
              semanticLabel: 'Attach',
              child: Container(
                width: InboxMotion.composeHeight,
                height: InboxMotion.composeHeight,
                decoration: BoxDecoration(
                  color: widget.attachOpen
                      ? InboxPalette.brand100
                      : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: InboxPalette.hairline),
                  boxShadow: InboxPalette.roundButton,
                ),
                child: Icon(
                  widget.attachOpen
                      ? Icons.close_rounded
                      : Icons.attach_file_rounded,
                  size: 20,
                  color: InboxPalette.brand600,
                ),
              ),
            ),
          if (!recording) const SizedBox(width: 8),
          Expanded(
            child: recording
                ? RecordingPill(
                    onDiscard: () =>
                        ref.read(voiceRecordingProvider.notifier).discard(),
                  )
                : _MessageField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    onTyping: widget.onTyping,
                    onSubmit: _send,
                  ),
          ),
          const SizedBox(width: 8),
          SendButton(
            onTap: _send,
            level: level,
            recording: recording,
            busy: _sendingText || record.isBusy,
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.paused,
    required this.recording,
    required this.onTap,
  });

  final bool paused;
  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // idle: white / brand · recording: brand (pause) · paused: tint (resume)
    final background = recording
        ? (paused ? InboxPalette.brand100 : InboxPalette.brand600)
        : Colors.white;
    final foreground = recording && !paused
        ? Colors.white
        : InboxPalette.brand600;
    final border = recording
        ? (paused ? InboxPalette.brand200 : Colors.transparent)
        : InboxPalette.hairline;

    return InboxPressable(
      onTap: onTap,
      semanticLabel: recording
          ? (paused ? 'Resume recording' : 'Pause recording')
          : 'Record a voice message',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: InboxMotion.spring,
        width: InboxMotion.composeHeight,
        height: InboxMotion.composeHeight,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: border),
          boxShadow: InboxPalette.roundButton,
        ),
        child: Icon(
          recording
              ? (paused ? Icons.mic_rounded : Icons.pause_rounded)
              : Icons.mic_none_rounded,
          size: 21,
          color: foreground,
        ),
      ),
    );
  }
}

class _MessageField extends StatefulWidget {
  const _MessageField({
    required this.controller,
    required this.focusNode,
    required this.onTyping,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTyping;
  final Future<void> Function() onSubmit;

  @override
  State<_MessageField> createState() => _MessageFieldState();
}

class _MessageFieldState extends State<_MessageField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: InboxMotion.easeOut,
      height: InboxMotion.composeHeight,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _focused
              ? InboxPalette.brand500.withValues(alpha: 0.45)
              : InboxPalette.hairline,
        ),
        boxShadow: _focused ? InboxPalette.fieldFocused : InboxPalette.field,
      ),
      child: Center(
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          maxLines: 1,
          maxLength: Message.bodyMax,
          buildCounter: (
            _, {
            required currentLength,
            required isFocused,
            maxLength,
          }) => null,
          textInputAction: TextInputAction.send,
          onChanged: (_) => widget.onTyping(),
          onSubmitted: (_) => widget.onSubmit(),
          cursorColor: AppColors.brand500,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1.3,
            color: AppColors.textPrimary,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: 'Message',
            hintStyle: TextStyle(
              fontSize: 14.5,
              color: InboxPalette.placeholder,
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
