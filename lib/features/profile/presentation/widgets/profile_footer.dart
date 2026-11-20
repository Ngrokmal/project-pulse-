import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// The sign-off at the bottom of the card: the wordmark on the brand gradient,
/// and the one sentence that says what Pulse is for.
class ProfileFooter extends StatelessWidget {
  const ProfileFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x00ECEAF4), AppColors.border, Color(0x00ECEAF4)],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ShaderMask(
          shaderCallback: (bounds) => AppColors.primaryGradient.createShader(
            Rect.fromLTWH(0, 0, bounds.width, bounds.height),
          ),
          child: Text(
            'PULSE',
            style: AppTypography.titleMedium.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 5.5,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Made for conversations that matter',
          style: AppTypography.micro.copyWith(
            fontSize: 11.5,
            letterSpacing: 0.3,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
