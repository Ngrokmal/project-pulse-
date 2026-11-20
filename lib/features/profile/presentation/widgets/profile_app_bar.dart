import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile_view_mode.dart';
import 'pulse_ui.dart';

/// The floating bar: back, title, the You/Visitor switch, code and menu.
///
/// It starts transparent over the hero and turns into porcelain the moment the
/// hero scrolls away, so the buttons never float as white-on-white.
class ProfileAppBar extends StatelessWidget {
  const ProfileAppBar({
    super.key,
    required this.scrolled,
    required this.mode,
    required this.onBack,
    required this.onMode,
    required this.onCode,
    required this.onMore,
  });

  final bool scrolled;
  final ProfileViewMode mode;
  final VoidCallback onBack;
  final ValueChanged<ProfileViewMode> onMode;
  final VoidCallback onCode;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final light = !scrolled;
    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.curve,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: BoxDecoration(
        color: scrolled
            ? AppColors.bg.withValues(alpha: 0.94)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: scrolled ? AppColors.border : Colors.transparent,
          ),
        ),
      ),
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              PulseGlassButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
                tooltip: 'Back',
                light: light,
              ),
              const Spacer(),
              AnimatedOpacity(
                duration: AppMotion.base,
                opacity: scrolled ? 1 : 0,
                child: Text(
                  'Profile',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Spacer(),
              _ViewPill(mode: mode, onMode: onMode, light: light),
              const SizedBox(width: 8),
              PulseGlassButton(
                icon: Icons.qr_code_2_rounded,
                onTap: onCode,
                tooltip: 'Your code',
                light: light,
              ),
              const SizedBox(width: 8),
              PulseGlassButton(
                icon: Icons.more_horiz_rounded,
                onTap: onMore,
                tooltip: 'More',
                light: light,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// You · Visitor. A preview switch, not a permission — it shows the card the way
/// somebody else would see it.
class _ViewPill extends StatelessWidget {
  const _ViewPill({
    required this.mode,
    required this.onMode,
    required this.light,
  });

  final ProfileViewMode mode;
  final ValueChanged<ProfileViewMode> onMode;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: light
            ? Colors.white.withValues(alpha: 0.16)
            : AppColors.brand100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: light
              ? Colors.white.withValues(alpha: 0.24)
              : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment('You', ProfileViewMode.owner, light),
          _segment('Visitor', ProfileViewMode.visitor, light),
        ],
      ),
    );
  }

  Widget _segment(String label, ProfileViewMode value, bool light) {
    final on = mode == value;
    return GestureDetector(
      onTap: () => onMode(value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          gradient: on && !light ? AppColors.primaryGradient : null,
          color: on && light ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: on
              ? const [
                  BoxShadow(
                    color: Color(0x2E7B5FED),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.micro.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: on
                ? (light ? AppColors.brand700 : Colors.white)
                : (light
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
