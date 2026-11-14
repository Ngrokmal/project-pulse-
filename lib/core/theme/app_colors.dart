import 'package:material_ui/material_ui.dart';

/// PULSE color tokens.
/// Values were measured from the supplied reference mockups
/// (k-means clustering over 1.33M brand pixels) — see design/tokens.json.
/// Only measured values are used; nothing here is an arbitrary guess.
class AppColors {
  AppColors._();

  // Brand purple scale
  static const brand50 = Color(0xFFF7F4FE);
  static const brand100 = Color(0xFFF3EFFD);
  static const brand200 = Color(0xFFE1D9FC);
  static const brand300 = Color(0xFFB8A2FA);
  static const brand400 = Color(0xFF9B8AF5);
  static const brand500 = Color(0xFF7B5FED); // PRIMARY
  static const brand600 = Color(0xFF5F3FDC);
  static const brand700 = Color(0xFF4F25C4);
  static const brand800 = Color(0xFF4818A8);
  static const brand900 = Color(0xFF2A0E6B);

  // Accent blue
  static const blue500 = Color(0xFF3768D2);
  static const blue300 = Color(0xFF9BABF6);
  static const blue100 = Color(0xFFD0DBFA);

  // Splash / hero navy
  static const navy700 = Color(0xFF191B73);
  static const navy800 = Color(0xFF0A0E51);
  static const navy900 = Color(0xFF03052D);

  // Light surfaces
  static const bg = Color(0xFFF8F7FB);
  static const card = Color(0xFFFFFFFF);
  static const cardAlt = Color(0xFFF3F0FD);
  static const border = Color(0xFFECEAF4);

  // Light text
  static const textPrimary = Color(0xFF151418);
  static const textSecondary = Color(0xFF3B3B40);
  static const textMuted = Color(0xFF8A8A93);
  static const onPrimary = Color(0xFFFFFFFF);

  // Status
  static const online = Color(0xFF17C653);
  static const success = Color(0xFF0C9C60);
  static const danger = Color(0xFFEF3E4A);
  static const warning = Color(0xFFF59E0B);

  // Dark surfaces / text
  static const darkBg = Color(0xFF0B0A14);
  static const darkSurface = Color(0xFF15131F);
  static const darkElevated = Color(0xFF1C1A2B);
  static const darkBorder = Color(0xFF2A2740);
  static const darkTextPrimary = Color(0xFFF5F4FA);
  static const darkTextMuted = Color(0xFFA5A2B8);

  /// Counterparty bubble and input fill (#F3F0FD, design/tokens.json).
  static const bubbleOther = Color(0xFFF3F0FD);
  static const inputFill = bubbleOther;

  // Gradients — the signature of the product
  static const gradientStart = Color(0xFF7B3FF2);
  static const gradientEnd = Color(0xFF3768D2);
  static const bubbleSelfStart = Color(0xFF5424D8);
  static const bubbleSelfEnd = Color(0xFF4818A8);

  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );

  static const bubbleSelfGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bubbleSelfStart, bubbleSelfEnd],
  );

  static const splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [navy700, navy800, navy900],
    stops: [0.0, 0.55, 1.0],
  );

  static const pageWashGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand50, Color(0xFFEEF1FE), bg],
    stops: [0.0, 0.55, 1.0],
  );
}
