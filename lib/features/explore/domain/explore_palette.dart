import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';

/// Tokens that exist only on Explore, taken 1:1 from
/// `pulse-explore-reference-v3.html`. Anything the app already owns (brand
/// scale, danger, muted, bg, border) is reused from [AppColors].
//
// Shadows: every CSS `spread: -N` in the reference is re-expressed here as a
// softer, smaller alpha with the same blur and offset. Negative spread is not
// Skia-safe on Android — it clips the shadow instead of sharpening it.
class ExplorePalette {
  ExplorePalette._();

  // --------------------------------------------------------------- surfaces
  /// `linear-gradient(180deg,#F7F5FE,#FBFAFE 38%,#F8F7FB)`.
  static const Color shellTop = Color(0xFFF7F5FE);
  static const Color shellMid = Color(0xFFFBFAFE);
  static const Color shellBottom = Color(0xFFF8F7FB);

  /// The soft violet bloom behind the header.
  static const Color shellBloom = Color(0xFFF3EEFE);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color hairline = Color(0xFFECEAF4);

  /// Ink used for names (the reference's `#191722`).
  static const Color ink = Color(0xFF191722);
  static const Color inkSoft = Color(0xFF5B5670);
  static const Color placeholder = Color(0xFFA9A6B8);
  static const Color metaInk = Color(0xFF8A87A0);
  static const Color chipInk = Color(0xFF4A4658);

  // ------------------------------------------------------------------ brand
  /// `--grad: 135deg, #9B8AF5 → #5F3FDC 55% → #4F25C4`.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9B8AF5), Color(0xFF5F3FDC), Color(0xFF4F25C4)],
    stops: [0, 0.55, 1],
  );

  static const LinearGradient brandDeep = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7B5FED), Color(0xFF4F25C4)],
  );

  static const Color brand100 = AppColors.brand100;
  static const Color brand200 = AppColors.brand200;
  static const Color brand300 = AppColors.brand300;
  static const Color brand400 = AppColors.brand400;
  static const Color brand500 = AppColors.brand500;
  static const Color brand600 = AppColors.brand600;
  static const Color brand700 = AppColors.brand700;
  static const Color muted = AppColors.textMuted;
  static const Color danger = AppColors.danger;
  static const Color online = AppColors.online;

  // ------------------------------------------------------- relation colours
  /// Requested: violet hairline + a violet-tinted pill.
  static const Color requestedBorder = Color(
    0x577B5FED,
  ); // rgba(123,95,237,.34)
  static const Color requestedTint = Color(0xFFFBFAFF);
  static const Color requestedPill = Color(0xFFF0EAFF);
  static const Color requestedInk = Color(0xFF6A4BD8);

  /// Asked you: a warmer violet edge, so it reads as "waiting on you".
  static const Color incomingBorder = Color(0x6B7B5FED); // rgba(123,95,237,.42)
  static const Color incomingTint = Color(0xFFF7F3FF);

  /// Friends: green edge, green pill ink.
  static const Color friendBorder = Color(0x5717C653); // rgba(23,198,83,.34)
  static const Color friendTint = Color(0xFFF7FEF9);
  static const Color friendInk = Color(0xFF0F7A57);

  static const Color pendingTint = Color(0xFFFFF6E5);
  static const Color pendingInk = Color(0xFF9A6A12);
  static const Color pendingLine = Color(0xFFE8B44C);

  static const Color badgeFriendBg = Color(0xFFE7F9EE);
  static const Color badgeFriendInk = Color(0xFF0F8A46);
  static const Color badgeHotBg = Color(0xFFFFF2E2);
  static const Color badgeHotInk = Color(0xFFA35E0C);
  static const Color badgeMeBg = Color(0xFFF0ECFB);

  // ------------------------------------------------------------- match meter
  static const Color meterTrack = Color(0xFFEDE8F9);
  static const LinearGradient meterFill = LinearGradient(
    colors: [Color(0xFF7B5FED), Color(0xFFB79BFF)],
  );

  // ------------------------------------------------------------------ toast
  static const Color toastFill = Color(0xFF1E1B29);
  static const Color toastInk = Color(0xFFFFFFFF);
  static const Color toastSubInk = Color(0xA9FFFFFF);
  static const Color toastBar = Color(0xFFA8ECFF);

  // ------------------------------------------------------------- mascot art
  static const Color mascotBlobStart = Color(0xFF9B8AF5);
  static const Color mascotBlobEnd = Color(0xFF5B3BD6);
  static const Color mascotCheek = Color(0x66FF8FB1);
  static const Color lensFace = Color(0xFFFBF8FF);
  static const Color lensFaceEnd = Color(0xFFEEE6FE);
  static const Color lensRim = Color(0xFFC9B6F7);
  static const Color lensInk = Color(0xFF3B2A6B);
  static const Color haloViolet = Color(0x4D7B5FED);
  static const Color haloCyan = Color(0x80A8ECFF);
  static const Color driftLetter = Color(0xFFB7A1F3);

  // --------------------------------------------------------------- avatars
  /// The eight gradients from the reference's `GRAD8`, cycled by id so a person
  /// keeps the same colour everywhere.
  static const List<LinearGradient> avatars = [
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFB1A0), Color(0xFFF87171), Color(0xFFC0392B)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7FD8FF), Color(0xFF3E9BF6), Color(0xFF2A54C7)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFC6A9FF), Color(0xFF8E6BF0), Color(0xFF5C2FBF)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFA7F3D0), Color(0xFF34C48E), Color(0xFF128A63)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFD37F), Color(0xFFF2A63C), Color(0xFFC8761A)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFC2E2), Color(0xFFF062A8), Color(0xFFB7236F)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFB9E6FF), Color(0xFF6AA8F5), Color(0xFF2F5FB8)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD8F39A), Color(0xFF8CC63F), Color(0xFF4E7C13)],
    ),
  ];

  static LinearGradient avatarFor(String seed) {
    if (seed.isEmpty) return avatars.first;
    final sum = seed.codeUnits.fold<int>(0, (a, c) => a + c);
    return avatars[sum % avatars.length];
  }

  // --------------------------------------------------------------- shadows
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x142A0E6B), blurRadius: 26, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0A151418), blurRadius: 8, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> cardLifted = [
    BoxShadow(color: Color(0x242A0E6B), blurRadius: 34, offset: Offset(0, 18)),
    BoxShadow(color: Color(0x0D151418), blurRadius: 10, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> field = [
    BoxShadow(color: Color(0x1A2A0E6B), blurRadius: 26, offset: Offset(0, 12)),
  ];

  /// Focus reads through depth, not a drawn ring.
  static const List<BoxShadow> fieldFocused = [
    BoxShadow(color: Color(0x335F3FDC), blurRadius: 30, offset: Offset(0, 14)),
    BoxShadow(color: Color(0x1F5F3FDC), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> primaryButton = [
    BoxShadow(color: Color(0x665F3FDC), blurRadius: 24, offset: Offset(0, 12)),
  ];

  static const List<BoxShadow> avatar = [
    BoxShadow(color: Color(0x3D2A0E6B), blurRadius: 20, offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> sheet = [
    BoxShadow(color: Color(0x522A0E6B), blurRadius: 46, offset: Offset(0, 24)),
  ];

  static const List<BoxShadow> toast = [
    BoxShadow(color: Color(0x4D0E0724), blurRadius: 34, offset: Offset(0, 18)),
  ];

  static Color brandAlpha(double alpha) =>
      AppColors.brand500.withValues(alpha: alpha);
  static Color dangerAlpha(double alpha) =>
      AppColors.danger.withValues(alpha: alpha);
  static Color onlineAlpha(double alpha) =>
      AppColors.online.withValues(alpha: alpha);
}
