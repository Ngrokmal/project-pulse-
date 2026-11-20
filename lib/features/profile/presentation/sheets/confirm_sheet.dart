import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import 'pulse_sheet.dart';

/// The last question before something irreversible.
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFDE8EA),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.priority_high_rounded,
                size: 20,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: AppTypography.headlineMedium.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          body,
          style: AppTypography.bodyMedium.copyWith(
            fontSize: 14,
            height: 1.55,
            color: AppColors.textMuted,
          ),
        ),
        SheetActions(
          confirmLabel: confirmLabel,
          destructive: true,
          onCancel: () => Navigator.of(context).pop(false),
          onConfirm: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
