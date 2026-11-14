import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';

/// Call history. Real empty state now; call records + provider-independent
/// call UI arrive with Phase 8.
class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                18,
                AppSpacing.screenX,
                10,
              ),
              child: Text('Calls', style: AppTypography.headlineMedium),
            ),
            const Divider(),
            const Expanded(
              child: PulseEmptyState(
                icon: Icons.call_outlined,
                title: 'No calls yet',
                message: 'Your voice and video call history will show up here.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
