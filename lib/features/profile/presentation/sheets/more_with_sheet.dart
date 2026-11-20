import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile.dart';
import 'pulse_sheet.dart';

/// One action offered by the sheet, with the sheet's own row rhythm.
class SheetAction {
  const SheetAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Runs *after* the sheet has closed. The sheet closes itself; a row must not
  /// pop again — doing that twice is what used to throw the whole page away and
  /// make every row here look broken.
  final VoidCallback onTap;
  final bool danger;
}

class MoreWithSheet extends StatelessWidget {
  const MoreWithSheet({
    super.key,
    required this.profile,
    required this.actions,
  });

  final Profile profile;
  final List<SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeading(
          title: 'More with ${profile.givenName}',
          subtitle: 'The small moves that make a conversation feel yours.',
        ),
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Material(
              color: AppColors.card,
              borderRadius: AppRadius.cardRadius,
              child: InkWell(
                borderRadius: AppRadius.cardRadius,
                onTap: () {
                  // Pop first so the action's own sheet is the next thing to
                  // rise, then run it on the next frame — a callback that opens
                  // a sheet in the same frame as a pop loses its route.
                  Navigator.of(context).pop();
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => action.onTap(),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.cardRadius,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: action.danger
                              ? const Color(0xFFFDE8EA)
                              : AppColors.brand100,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          action.icon,
                          size: 18,
                          color: action.danger
                              ? AppColors.danger
                              : AppColors.brand600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              action.title,
                              style: AppTypography.titleMedium.copyWith(
                                fontSize: 14.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              action.subtitle,
                              style: AppTypography.micro.copyWith(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
