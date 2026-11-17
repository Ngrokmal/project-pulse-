import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/message.dart';
import '../../../force_audio/presentation/force_audio_bubble.dart';
import '../../../media/presentation/media_bubble.dart';
import '../../domain/inbox_delivery.dart';
import '../../domain/inbox_timeline.dart';
import 'bubble_shell.dart';
import 'inbox_entrance.dart';
import 'text_bubble.dart';
import 'voice_note_bubble.dart';

/// One timeline row: alignment, width cap, the failure badge/retry line and the
/// long-press-to-delete affordance.
///
/// Layout is transform/opacity only — the entrance animation runs once, and only
/// for rows that are actually new (see [_isFreshRow]).
class MessageRow extends StatelessWidget {
  const MessageRow({
    super.key,
    required this.cell,
    required this.onRetry,
    required this.onDelete,
    this.myName,
    this.peerName,
  });

  final InboxCell cell;
  final String? myName;
  final String? peerName;
  final VoidCallback onRetry;
  final VoidCallback? onDelete;

  bool get _isFreshRow =>
      DateTime.now().difference(cell.createdAt) < const Duration(seconds: 8);

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.79;
    final failed = cell.delivery == InboxDelivery.failed;

    Widget bubble = _buildBubble(maxWidth, failed);

    bubble = GestureDetector(
      onLongPress: cell.mine ? onDelete : null,
      child: bubble,
    );

    if (_isFreshRow) {
      bubble = InboxEntrance(child: bubble);
    }

    return Align(
      alignment: cell.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: cell.mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              bubble,
              if (failed)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: _FailBadge(onTap: onRetry),
                ),
            ],
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: GestureDetector(
                onTap: onRetry,
                child: Text(
                  'Tap to retry',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBubble(double maxWidth, bool failed) {
    final message = cell.message;

    if (message.isDeleted) {
      return TextBubble(
        message: message,
        mine: cell.mine,
        delivery: cell.delivery,
        stackPrev: cell.stackPrev,
        stackNext: cell.stackNext,
        maxWidth: maxWidth,
      );
    }

    switch (message.kind) {
      case MessageKind.audio:
        return VoiceNoteBubble(
          message: message,
          mine: cell.mine,
          stackPrev: cell.stackPrev,
          stackNext: cell.stackNext,
        );
      case MessageKind.forceAudio:
        return BubbleShell(
          mine: cell.mine && !failed,
          failed: failed,
          stackPrev: cell.stackPrev,
          stackNext: cell.stackNext,
          maxWidth: maxWidth,
          child: ForceAudioBubble(
            messageId: message.id,
            mine: cell.mine,
            durationMs: message.durationMs,
          ),
        );
      case MessageKind.image:
      case MessageKind.video:
      case MessageKind.file:
        return BubbleShell(
          mine: cell.mine && !failed,
          failed: failed,
          stackPrev: cell.stackPrev,
          stackNext: cell.stackNext,
          maxWidth: maxWidth,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
          child: MediaBubble(
            message: message,
            mine: cell.mine && !failed,
            myName: myName,
            peerName: peerName,
          ),
        );
      case MessageKind.text:
        return TextBubble(
          message: message,
          mine: cell.mine,
          delivery: cell.delivery,
          stackPrev: cell.stackPrev,
          stackNext: cell.stackNext,
          sweep: cell.delivery == InboxDelivery.pending,
          maxWidth: maxWidth,
        );
    }
  }
}

/// `@keyframes popIn`: the red badge that takes the corner of a failed bubble.
class _FailBadge extends StatelessWidget {
  const _FailBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      builder: (context, value, child) =>
          Transform.scale(scale: value.clamp(0.0, 1.2), child: child),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.danger,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x66EF3E4A),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.priority_high_rounded,
            size: 13,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
