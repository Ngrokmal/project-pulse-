import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Opens the standard sheet: porcelain, 28 px shoulders, a grab handle, and it
/// rises over the page instead of replacing it.
Future<T?> showPulseSheet<T>({
  required BuildContext context,
  required Widget child,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66201C33),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: _SheetFrame(child: child),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33201C33),
            blurRadius: 34,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 9),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE4E1EE),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                14,
                AppSpacing.screenX,
                MediaQuery.paddingOf(context).bottom + 18,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// The heading every sheet shares.
class SheetHeading extends StatelessWidget {
  const SheetHeading({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: AppTypography.headlineMedium.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: AppTypography.bodyMedium.copyWith(
          fontSize: 13.5,
          height: 1.5,
          color: AppColors.textMuted,
        ),
      ),
      const SizedBox(height: 18),
    ],
  );
}

/// Cancel · primary, in the sheet's own footer.
class SheetActions extends StatelessWidget {
  const SheetActions({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
    this.busy = false,
    this.destructive = false,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: busy ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: AppTypography.buttonLabel.copyWith(fontSize: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: destructive
                      ? const LinearGradient(
                          colors: [Color(0xFFF0566A), AppColors.danger],
                        )
                      : AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  boxShadow: AppShadows.glowPrimary,
                ),
                child: TextButton(
                  onPressed: busy ? null : onConfirm,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          confirmLabel,
                          style: AppTypography.buttonLabel.copyWith(
                            fontSize: 14.5,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
