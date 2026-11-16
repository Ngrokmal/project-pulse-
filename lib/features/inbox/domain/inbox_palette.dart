import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';

/// Tokens that exist only on the personal inbox screen, lifted 1:1 from
/// `pulse-inbox-reference-v3.html`. Everything that the rest of the app already
/// owns (brand scale, danger, muted, bg) is reused from [AppColors]; nothing is
/// re-invented here.
class InboxPalette {
  InboxPalette._();

  /// The "seen" / playing accent from the reference (`--cyan`).
  static const Color cyan = Color(0xFFA8ECFF);
  static const Color cyanInk = Color(0xFF0B2E3A);

  /// Chat shell background: three stops of the reference linear-gradient.
  static const Color shellTop = Color(0xFFFBFAFF);
  static const Color shellMid = Color(0xFFF6F4FC);
  static const Color shellBottom = Color(0xFFF2EFFA);

  /// The radial bloom at the very top of the shell and of the home list.
  static const Color shellBloom = Color(0xFFF7F3FE);

  /// Header glass: rgba(252,251,255,.86). Flutter has no backdrop blur that
  /// matches `backdrop-filter` cheaply, so the fill is opaque enough to read on
  /// its own and the blur is applied with ImageFiltered only where it is cheap.
  static const Color headerFill = Color(0xF2FCFBFF);

  /// Deep navy ink used for names and icon glyphs (`#141452`).
  static const Color ink = Color(0xFF141452);
  static const Color placeholder = Color(0xFFA9A7B4);

  /// Delivery + queue accents.
  static const Color queuedAmber = Color(0xFFF6C479);
  static const Color offlineBg = Color(0xFFFFF6E8);
  static const Color offlineInk = Color(0xFF8A4B12);
  static const Color ghost = Color(0xFFC9C5D6);

  /// `--grad`, the signature three-stop brand gradient (135°).
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9B8AF5), Color(0xFF5F3FDC), Color(0xFF4F25C4)],
    stops: [0, 0.55, 1],
  );

  /// Avatar gradients, cycled deterministically per peer id.
  static const List<LinearGradient> avatars = [
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF8E7BF6), Color(0xFF5F3FDC)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF5A3C7), Color(0xFFC4559A)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF7ED0C1), Color(0xFF2F9E8B)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFF6C479), Color(0xFFD08A2A)],
    ),
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF9DB4F5), Color(0xFF4A63C4)],
    ),
  ];

  static LinearGradient avatarFor(String seed) =>
      avatars[seed.isEmpty
          ? 0
          : seed.codeUnits.fold<int>(0, (a, c) => a + c) % avatars.length];

  // ------------------------------------------------------------------ shadows
  // CSS negative spreads are not Skia-safe, so each one is re-expressed as a
  // smaller alpha with the same blur and offset: same light, no clipped shadow.
  static const List<BoxShadow> bubbleIn = [
    BoxShadow(color: Color(0x242A0E6B), blurRadius: 22, offset: Offset(0, 10)),
  ];
  static const List<BoxShadow> bubbleOut = [
    BoxShadow(color: Color(0x5C5F3FDC), blurRadius: 30, offset: Offset(0, 16)),
  ];

  /// Bubble that is currently playing: the out shadow plus a 1px cyan edge.
  static const List<BoxShadow> bubblePlaying = [
    BoxShadow(color: Color(0x6B5F3FDC), blurRadius: 38, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x38A8ECFF), blurRadius: 0, spreadRadius: 1),
  ];

  static const List<BoxShadow> field = [
    BoxShadow(color: Color(0x162A0E6B), blurRadius: 28, offset: Offset(0, 14)),
  ];
  static const List<BoxShadow> fieldFocused = [
    BoxShadow(color: Color(0x4D5F3FDC), blurRadius: 30, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x1F7B5FED), blurRadius: 0, spreadRadius: 3),
  ];
  static const List<BoxShadow> roundButton = [
    BoxShadow(color: Color(0x1F2A0E6B), blurRadius: 24, offset: Offset(0, 12)),
  ];
  static const List<BoxShadow> send = [
    BoxShadow(color: Color(0x665F3FDC), blurRadius: 28, offset: Offset(0, 16)),
  ];
  static const List<BoxShadow> sheet = [
    BoxShadow(color: Color(0x4D2A0E6B), blurRadius: 50, offset: Offset(0, 26)),
  ];

  /// The recorder pill's resting shadow; the live level adds the halo on top.
  static const List<BoxShadow> recorder = [
    BoxShadow(color: Color(0x2EEF3E4A), blurRadius: 28, offset: Offset(0, 14)),
  ];

  static const Color bubbleOutBorder = Color(0x33FFFFFF);
  static const Color hairline = Color(0xFFECEAF4);
  static const Color dangerTint = Color(0x14EF3E4A);
  static const Color brandTint = Color(0x147B5FED);
  static const Color brandTintStrong = Color(0x247B5FED);

  // Brand aliases, so the widgets read like the CSS variables they replace.
  static const Color brand100 = AppColors.brand100;
  static const Color brand200 = AppColors.brand200;
  static const Color brand300 = AppColors.brand300;
  static const Color brand400 = AppColors.brand400;
  static const Color brand500 = AppColors.brand500;
  static const Color brand600 = AppColors.brand600;
  static const Color brand700 = AppColors.brand700;
  static const Color danger = AppColors.danger;
  static const Color muted = AppColors.textMuted;

  static Color dangerAlpha(double a) => AppColors.danger.withValues(alpha: a);
  static Color brandAlpha(double a) => AppColors.brand500.withValues(alpha: a);
}
