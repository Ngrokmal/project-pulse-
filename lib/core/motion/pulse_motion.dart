import 'package:material_ui/material_ui.dart';

/// Motion tokens for the v4 home/chat redesign.
///
/// Every number here was read off `pulse-home-reference-v4.html`; see
/// `docs/V4_MOTION_SPEC.md` for the mapping table. Keep that file and this
/// class in sync — the HTML is the source of truth.
class PulseMotion {
  const PulseMotion._();

  // ---------------------------------------------------------------- curves
  /// `cubic-bezier(.22, 1.18, .36, 1)` — the signature overshoot.
  static const Curve spring = Cubic(0.22, 1.18, 0.36, 1);

  /// `cubic-bezier(.16, 1, .3, 1)` — the settle curve.
  static const Curve easeOut = Cubic(0.16, 1, 0.3, 1);

  /// `cubic-bezier(.25, .7, .3, 1)` — the radiating logo rings.
  static const Curve ring = Cubic(0.25, 0.7, 0.3, 1);

  // ------------------------------------------------------------- durations
  static const Duration rowEnter = Duration(milliseconds: 620);
  static const Duration rowStagger = Duration(milliseconds: 26);
  static const Duration rowShift = Duration(milliseconds: 560);
  static const Duration rowLift = Duration(milliseconds: 540);
  static const Duration pressIn = Duration(milliseconds: 130);
  static const Duration pressHold = Duration(milliseconds: 165);

  static const Duration ripple = Duration(milliseconds: 1050);
  static const Duration drop = Duration(milliseconds: 780);
  static const Duration ringWave = Duration(milliseconds: 920);
  static const Duration ringWaveTwo = Duration(milliseconds: 1020);
  static const Duration ringWaveDelay = Duration(milliseconds: 140);
  static const Duration bead = Duration(milliseconds: 720);
  static const Duration beadStagger = Duration(milliseconds: 45);

  static const Duration searchOpen = Duration(milliseconds: 480);
  static const Duration chatSlide = Duration(milliseconds: 520);
  static const Duration bubbleIn = Duration(milliseconds: 580);
  static const Duration bubbleStagger = Duration(milliseconds: 45);

  // -------------------------------------------------------------- geometry
  static const double rowRadius = 22;
  static const double avatarSize = 62;
  static const double rowGap = 10;

  static const double rowEnterRise = 20; // px the card rises from
  static const double rowEnterScale = 0.972;

  static const double pressSink = 2.5; // px down while the finger is held
  static const double pressScale = 0.99;

  static const double onlineDot = 16;
  static const double unreadDot = 22;

  /// Ripple base diameter (CSS `width: 22px`).
  /// How far content dissolves at the top / bottom edge of a scrolling list.
  static const double featherTop = 26;
  static const double featherBottom = 42;

  static const double rippleBase = 22;

  // ------------------------------------------------------------------ blur
  /// Blur is real (`ImageFilter.blur`) unless this is switched off. Off keeps
  /// every other part of the motion and only drops the expensive layer, so a
  /// slow phone degrades instead of stuttering.
  static bool blurEnabled = true;

  /// Collapses to 0 when blur is disabled.
  static double blur(double px) => blurEnabled ? px : 0;

  // ----------------------------------------------------------------- ink
  static const Color nameInk = Color(0xFF141452);
  static const Color previewInk = Color(0xFF6F6C80);

  // --------------------------------------------------------------- shadows
  /// The three stacked shadows from `.row` in the reference.
  static const List<BoxShadow> rowShadow = [
    BoxShadow(
      color: Color(0x8C5F3FDC), // rgba(95,63,220,.55)
      blurRadius: 26,
      spreadRadius: -16,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0B151418), // rgba(21,20,24,.045)
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
    BoxShadow(
      color: Color(0x735F3FDC), // rgba(95,63,220,.45)
      blurRadius: 14,
      spreadRadius: -16,
      offset: Offset(0, 14),
    ),
  ];

  /// The softer shadow the card drops to while pressed.
  static const List<BoxShadow> rowShadowPressed = [
    BoxShadow(
      color: Color(0x805F3FDC),
      blurRadius: 14,
      spreadRadius: -12,
      offset: Offset(0, 6),
    ),
    BoxShadow(color: Color(0x08151418), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// `linear-gradient(180deg, rgba(255,255,255,.94), rgba(255,255,255,.66))`
  static const LinearGradient rowSurface = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xF0FFFFFF), Color(0xA8FFFFFF)],
  );
}
