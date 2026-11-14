import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/push_message_controller.dart';
import '../domain/push_message.dart';

/// In-app presentation of a push that arrived while Pulse is open. Android shows
/// nothing by itself in the foreground, so this is the delivery surface (§31).
/// Force Audio pushes are labelled and routed to the Inbox for now; the
/// takeover screen lands with the Force Audio work.
class PushBanner extends ConsumerWidget {
  const PushBanner({super.key, this.onOpenInbox});

  final VoidCallback? onOpenInbox;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(pushMessageProvider);
    if (message == null) return const SizedBox.shrink();

    final isForceAudio = message.kind == PushKind.forceAudio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenX,
        10,
        AppSpacing.screenX,
        0,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.cardRadius,
          onTap: () {
            ref.read(pushMessageProvider.notifier).dismiss();
            onOpenInbox?.call();
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Row(
              children: [
                Icon(
                  isForceAudio
                      ? Icons.volume_up_rounded
                      : Icons.notifications_active_rounded,
                  color: AppColors.onPrimary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.onPrimary,
                        ),
                      ),
                      if (message.hasBody)
                        Text(
                          message.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.onPrimary.withValues(alpha: 0.85),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: () =>
                      ref.read(pushMessageProvider.notifier).dismiss(),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.onPrimary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
