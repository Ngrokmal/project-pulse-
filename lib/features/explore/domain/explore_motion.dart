import 'package:material_ui/material_ui.dart';

/// Durations, curves and geometry for Explore, read off
/// `pulse-explore-reference-v3.html`. One source of truth: a widget never
/// writes a raw `Duration` or a magic distance.
class ExploreMotion {
  ExploreMotion._();

  // ------------------------------------------------------------------ curves
  /// `--spring: cubic-bezier(.22,1.18,.36,1)`.
  static const Curve spring = Cubic(0.22, 1.18, 0.36, 1);

  /// `--ease-out: cubic-bezier(.16,1,.3,1)`.
  static const Curve easeOut = Cubic(0.16, 1, 0.3, 1);

  /// The gentle settle used by the mascot and the breathing halos.
  static const Curve breathe = Curves.easeInOutSine;

  // ---------------------------------------------------------------- entering
  static const Duration rowEnter = Duration(milliseconds: 520);
  static const Duration rowStagger = Duration(milliseconds: 55);
  static const Duration rowEnterFast = Duration(milliseconds: 420);

  /// Cards rise 14 px and scale .97 → 1, exactly like `.card` in the sheet.
  static const double enterRise = 14;
  static const double enterScale = 0.97;

  // --------------------------------------------------------------- segments
  static const Duration segmentSlide = Duration(milliseconds: 520);
  static const Duration segmentSquish = Duration(milliseconds: 220);

  // ------------------------------------------------------------------ swipe
  /// Past this distance a swipe commits; before it the card springs home.
  static const double swipeCommit = 92;
  static const double swipeResistAfter = 190;

  /// One degree of tilt per this many pixels dragged.
  static const double swipeTiltPerPixel = 26;

  /// How far the accept/decline underlay is drawn before a commit.
  static const double swipeUnderlayInset = 0;

  static const Duration swipeSettle = Duration(milliseconds: 380);
  static const Duration swipeRelease = Duration(milliseconds: 260);

  // ------------------------------------------------------------------ press
  static const Duration press = Duration(milliseconds: 130);

  // ---------------------------------------------------------------- actions
  /// Accept reads as a moment: morph 380, ring 900, collapse 420.
  static const Duration acceptMorph = Duration(milliseconds: 380);
  static const Duration acceptRing = Duration(milliseconds: 950);
  static const Duration cardCollapse = Duration(milliseconds: 420);

  /// Sending from the search sheet: spinner → requested pill.
  static const Duration requestSending = Duration(milliseconds: 620);

  // ------------------------------------------------------------------ toast
  static const Duration toastIn = Duration(milliseconds: 280);
  static const Duration toastOut = Duration(milliseconds: 220);

  /// The cyan bar drains over this time, and the toast leaves with it.
  static const Duration toastLife = Duration(milliseconds: 4200);

  // --------------------------------------------------------------- sparkles
  static const int sparkCount = 12;
  static const Duration sparkLife = Duration(milliseconds: 760);
  static const double sparkTravel = 46;

  // ------------------------------------------------------------------- chip
  static const Duration newChipHold = Duration(milliseconds: 2600);
  static const Duration newChipFade = Duration(milliseconds: 380);

  // ----------------------------------------------------------------- search
  /// The sheet grows out of the field, then settles.
  /// The honest presence dot breathes while it is green (2.4 s, reversed).
  static const Duration liveDotPulse = Duration(milliseconds: 2400);

  /// The header wordmark: one arrival, then a slow sheen across the letters.
  static const Duration wordmarkEnter = Duration(milliseconds: 620);
  static const Duration wordmarkSweep = Duration(milliseconds: 4200);

  static const Duration sheetOpen = Duration(milliseconds: 480);
  static const Duration sheetClose = Duration(milliseconds: 260);
  static const double sheetOriginFactor = 0.18;

  /// A fake-but-honest floor: the server answers when it answers, but the
  /// skeleton never flashes for less than this, which is what makes it feel
  /// calm instead of jittery.
  static const Duration searchMinimum = Duration(milliseconds: 380);

  static const Duration skeletonSweep = Duration(milliseconds: 1150);
  static const Duration matchBarFill = Duration(milliseconds: 850);
  static const Duration matchBarStagger = Duration(milliseconds: 55);

  /// The magnifier scans, the letters drift away, the puffs breathe out.
  static const Duration mascotScan = Duration(milliseconds: 4400);
  static const Duration mascotBlink = Duration(milliseconds: 4200);
  static const Duration mascotBob = Duration(milliseconds: 5600);
  static const Duration mascotHalo = Duration(milliseconds: 4600);
  static const Duration driftLetter = Duration(milliseconds: 5200);

  // -------------------------------------------------------------- geometry
  static const double headerHeight = 168;
  static const double fieldHeight = 46;
  static const double segmentHeight = 44;
  static const double avatarSize = 44;
  static const double cardRadius = 18;
  static const double fieldRadius = 16;
  static const double pillRadius = 999;
  static const double toastRadius = 16;

  /// Bottom padding every list needs so the last row clears the toast and the
  /// navigation bar.
  static const double listBottomPadding = 128;

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: 20);
}
