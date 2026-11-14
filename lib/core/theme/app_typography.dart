import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

/// Type scale from the design system (design/tokens.json §typography).
/// Poppins is bundled for display/headings; body uses the platform font
/// (Roboto on Android) which keeps APK size small and text crisp.
class AppTypography {
  AppTypography._();

  static const String display = 'Poppins';
  static const String body = 'Roboto';

  static const displaySmall = TextStyle(
    fontFamily: display,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.6,
    color: AppColors.textPrimary,
  );

  static const headlineMedium = TextStyle(
    fontFamily: display,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
    color: AppColors.textPrimary,
  );

  static const titleLarge = TextStyle(
    fontFamily: display,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static const titleMedium = TextStyle(
    fontFamily: body,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.textPrimary,
  );

  static const bodyLarge = TextStyle(
    fontFamily: body,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  static const bodyMedium = TextStyle(
    fontFamily: body,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  static const caption = TextStyle(
    fontFamily: body,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textMuted,
  );

  static const micro = TextStyle(
    fontFamily: body,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    height: 1.2,
    color: AppColors.textMuted,
  );

  static const buttonLabel = TextStyle(
    fontFamily: display,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: AppColors.onPrimary,
  );
}
