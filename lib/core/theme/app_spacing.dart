import 'package:material_ui/material_ui.dart';

/// Spacing / radius / elevation / motion tokens (design/tokens.json).
class AppSpacing {
  AppSpacing._();
  static const double unit = 4;
  static const double screenX = 20;
  static const double sectionGap = 24;
  static const double listRowGap = 12;
  static const double bubbleGap = 6;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  AppRadius._();
  static const double xs = 8;
  static const double sm = 12;
  static const double input = 16;
  static const double bubble = 18;
  static const double card = 20;
  static const double sheet = 28;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius inputRadius = BorderRadius.all(
    Radius.circular(input),
  );
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );
}

class AppShadows {
  AppShadows._();
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F3C2878), blurRadius: 16, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> glowPrimary = [
    BoxShadow(color: Color(0x527B5FED), blurRadius: 24, offset: Offset(0, 10)),
  ];
  static const List<BoxShadow> fab = [
    BoxShadow(color: Color(0x614F25C4), blurRadius: 28, offset: Offset(0, 12)),
  ];
}

/// Motion tokens (§28). Durations are short on purpose: animation must never
/// delay a meaningful action.
class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);
  static const Duration splashHold = Duration(milliseconds: 1500);
  static const Curve curve = Cubic(0.22, 1, 0.36, 1);

  /// Respect OS "remove animations" (accessibility, §15/§28).
  static bool reducedMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
