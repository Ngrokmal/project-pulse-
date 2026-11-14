import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pulse_mark.dart';
import '../../../core/widgets/state_views.dart';

/// Inbox. Phase 1 ships the real shell, header and empty state; conversations,
/// filters, unread badges and the Force Audio bell arrive with the messaging
/// phases (4 and 6). Nothing here pretends to have data it does not have.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                12,
                AppSpacing.screenX,
                8,
              ),
              child: Row(
                children: [
                  const PulseMark(size: 34),
                  const SizedBox(width: 10),
                  Text(
                    'Pulse',
                    style: AppTypography.headlineMedium.copyWith(fontSize: 24),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: null,
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: null,
                    icon: const Icon(Icons.notifications_none_rounded),
                  ),
                ],
              ),
            ),
            const Divider(),
            const Expanded(
              child: PulseEmptyState(
                icon: Icons.forum_outlined,
                title: 'No conversations yet',
                message: 'Your chats and groups will appear here. Messaging arrives in the next build.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
