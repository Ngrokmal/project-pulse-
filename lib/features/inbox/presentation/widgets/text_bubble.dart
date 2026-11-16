import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/message.dart';
import '../../domain/inbox_delivery.dart';
import 'bubble_shell.dart';
import 'delivery_ticks.dart';

/// A plain text bubble: 14.6 px / 1.42, timestamp at 10.5 px with the tick after
/// it, and the reference's italic tombstone for a deleted message.
class TextBubble extends StatelessWidget {
  const TextBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.delivery,
    this.stackPrev = false,
    this.stackNext = false,
    this.sweep = false,
    this.maxWidth,
  });

  final Message message;
  final bool mine;
  final InboxDelivery delivery;
  final bool stackPrev;
  final bool stackNext;
  final bool sweep;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final deleted = message.isDeleted;
    final failed = delivery == InboxDelivery.failed;
    final textColor = failed
        ? AppColors.textSecondary
        : mine
        ? Colors.white
        : AppColors.textPrimary;

    return BubbleShell(
      mine: mine && !failed,
      failed: failed,
      stackPrev: stackPrev,
      stackNext: stackNext,
      sweep: sweep,
      maxWidth: maxWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            deleted ? 'Message deleted' : (message.body ?? ''),
            style: TextStyle(
              fontSize: 14.6,
              height: 1.42,
              letterSpacing: -0.1,
              fontWeight: FontWeight.w400,
              color: deleted ? AppColors.textMuted : textColor,
              fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat.Hm().format(message.createdAt),
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: mine && !failed
                      ? Colors.white.withValues(alpha: 0.92)
                      : AppColors.textMuted,
                ),
              ),
              if (mine && !deleted) ...[
                const SizedBox(width: 4),
                DeliveryTicks(state: delivery, mine: mine && !failed),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
