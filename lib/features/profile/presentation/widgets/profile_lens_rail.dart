import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile_lens.dart';
import '../../domain/profile_view_mode.dart';

/// The lens rail: Story · People · Media · Settings (Safety for visitors).
///
/// The indicator is one gradient pill that slides, which is why a lens change
/// feels like turning a dial rather than swapping a page.
class ProfileLensRail extends StatelessWidget {
  const ProfileLensRail({
    super.key,
    required this.lens,
    required this.mode,
    required this.onSelect,
  });

  final ProfileLens lens;
  final ProfileViewMode mode;
  final ValueChanged<ProfileLens> onSelect;

  @override
  Widget build(BuildContext context) {
    const lenses = ProfileLens.values;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = constraints.maxWidth / lenses.length;
          return Stack(
            children: [
              AnimatedAlign(
                duration: AppMotion.base,
                curve: AppMotion.curve,
                alignment: Alignment(
                  -1 + 2 * (lens.index / (lenses.length - 1)),
                  0,
                ),
                child: AnimatedContainer(
                  duration: AppMotion.base,
                  curve: AppMotion.curve,
                  width: slot - 4,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x337B5FED),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in lenses)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelect(item),
                        child: SizedBox(
                          height: 36,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: AppMotion.base,
                              style: AppTypography.micro.copyWith(
                                fontSize: 12.5,
                                fontWeight: item == lens
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: item == lens
                                    ? Colors.white
                                    : AppColors.textMuted,
                              ),
                              child: Text(item.label(mode)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
