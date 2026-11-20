import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile.dart';
import 'pulse_sheet.dart';

/// "Your code": a real, scannable code for the profile link.
///
/// The encoder is `qr_flutter`, so what a camera reads here is the actual
/// `pulse.app/@handle` string — not a decorative square.
class QrCodeSheet extends StatelessWidget {
  const QrCodeSheet({super.key, required this.profile, required this.onCopyLink});

  final Profile profile;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    final link = profile.shareLink ?? 'pulse.app';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeading(
          title: 'Your code',
          subtitle:
              'A camera pointed here opens this profile — nothing to type.',
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.card,
            ),
            child: QrImageView(
              data: link,
              version: QrVersions.auto,
              size: 188,
              gapless: true,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.textPrimary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            link,
            style: AppTypography.caption.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.brand700,
            ),
          ),
        ),
        SheetActions(
          confirmLabel: 'Copy link',
          onCancel: () => Navigator.of(context).pop(false),
          onConfirm: () {
            onCopyLink();
            Navigator.of(context).pop(true);
          },
        ),
      ],
    );
  }
}
