import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile.dart';
import 'pulse_sheet.dart';

/// The avatar, up close, with the one action that changes it.
class ProfilePhotoSheet extends StatelessWidget {
  const ProfilePhotoSheet({
    super.key,
    required this.profile,
    required this.onChange,
  });

  final Profile profile;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetHeading(
          title: 'Profile photo',
          subtitle:
              'Your initials on the Pulse gradient. A real photo replaces them '
              'the moment you add one.',
        ),
        Center(
          child: Container(
            width: 132,
            height: 132,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.brand400, AppColors.brand700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: profile.avatarUrl == null || profile.avatarUrl!.isEmpty
                ? Text(
                    profile.initials,
                    style: AppTypography.displaySmall.copyWith(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Image.network(profile.avatarUrl!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 8),
        SheetActions(
          confirmLabel: 'Change photo',
          onCancel: () => Navigator.of(context).pop(false),
          onConfirm: onChange,
        ),
      ],
    );
  }
}
