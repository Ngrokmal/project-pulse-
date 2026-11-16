import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Durations, curves and — most importantly — the *level → geometry* map of the
/// reference. Every animated value on this screen is derived from one of the
/// constants below, so there is exactly one source of truth for the motion.
class InboxMotion {
  InboxMotion._();

  // ------------------------------------------------------------------- curves
  /// `--spring: cubic-bezier(.22,1.18,.36,1)` — overshoots on purpose.
  static const Curve spring = Cubic(0.22, 1.18, 0.36, 1);

  /// `--ease-out: cubic-bezier(.16,1,.3,1)`
  static const Curve easeOut = Cubic(0.16, 1, 0.3, 1);

  // ---------------------------------------------------------------- durations
  static const Duration bubbleIn = Duration(milliseconds: 580);
  static const Duration bubbleInFast = Duration(milliseconds: 420);
  static const Duration sendSweep = Duration(milliseconds: 900);
  static const Duration sendSweepDelay = Duration(milliseconds: 60);
  static const Duration failShake = Duration(milliseconds: 500);
  static const Duration noteIn = Duration(milliseconds: 550);
  static const Duration popIn = Duration(milliseconds: 340);
  static const Duration headerCompact = Duration(milliseconds: 280);
  static const Duration slowBar = Duration(milliseconds: 340);
  static const Duration chipSheen = Duration(milliseconds: 4200);
  static const Duration presencePulse = Duration(milliseconds: 1200);
  static const Duration typeDot = Duration(milliseconds: 1150);
  static const Duration typeDotStagger = Duration(milliseconds: 140);
  static const Duration recIn = Duration(milliseconds: 300);
  static const Duration recOut = Duration(milliseconds: 220);
  static const Duration hintWave = Duration(milliseconds: 1450);
  static const Duration hintStagger = Duration(milliseconds: 46);
  static const Duration orbit = Duration(milliseconds: 2100);
  static const Duration waveBreath = Duration(milliseconds: 1700);
  static const Duration avatarOrbit = Duration(milliseconds: 4800);
  static const Duration avatarHalo = Duration(milliseconds: 3600);
  static const Duration ripple = Duration(milliseconds: 660);
  static const Duration tapRipple = Duration(milliseconds: 660);

  /// One frame of the level smoother. 60 fps, like `requestAnimationFrame`.
  static const Duration frame = Duration(milliseconds: 16);

  // -------------------------------------------------------------- geometry
  /// 22 bars in the recorder and in every voice bubble (reference `new Array(22)`).
  static const int waveformBars = 22;

  /// Recorder pill: 46 px tall, trash inset 7 px, 32 px square.
  static const double composeHeight = 46;
  static const double trashSize = 32;
  static const double trashInset = 7;
  static const double recorderPaddingLeft = 11;
  static const double recorderPaddingRight = 47;

  /// Bubble: max-width 79%, padding 9 13 7, radius 18 with a 7 px tail.
  static const double bubbleMaxWidthFactor = 0.79;
  static const double bubbleRadius = 18;
  static const double bubbleTail = 7;
  static const double bubbleStack = 8;
  static const EdgeInsets bubblePadding = EdgeInsets.fromLTRB(13, 9, 13, 7);
  static const EdgeInsets audioBubblePadding = EdgeInsets.fromLTRB(
    10,
    8,
    10,
    6,
  );

  /// The hint runs at 9.5 px / 800 weight with a 0.1 px tracking (reference).
  static const TextStyle hintStyle = TextStyle(
    fontSize: 9.5,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.1,
    fontFamily: 'Roboto',
  );

  /// Space between hint words, in px (reference `.ltr.space{width:3px}`).
  static const double hintSpace = 3;

  // ------------------------------------------------ level → geometry (0..1)
  /// Hint letters: translateY up to −3.4 px, scale up to 1.15, opacity .6 → 1.
  static double hintLift(double level) => -3.4 * level;
  static double hintScale(double level) => 1 + 0.15 * level;
  static double hintOpacity(double level) => 0.6 + 0.4 * level;

  /// Hint glow: `drop-shadow(0 0 lvl*8px …)`.
  static double hintGlow(double level) => 8 * level;
  static double hintGlowAlpha(double level) => 0.6 * level;

  /// Recorder halo: `0 0 0 lvl*5px rgba(danger, .16 + lvl*.2)`.
  static double haloSpread(double level) => 5 * level;
  static double haloAlpha(double level) => 0.16 + 0.2 * level;

  /// Send bloom while recording: `0 0 lvl*18px rgba(brand, lvl*.8)`.
  static double sendBloom(double level) => 18 * level;
  static double sendBloomAlpha(double level) => 0.8 * level;

  /// Voice meter: 3 → 12 px, 5 → 12 px, 4 → 12 px.
  static double meterFirst(double level) => 3 + 9 * level;
  static double meterSecond(double level) => 5 + 7 * level;
  static double meterThird(double level) => 4 + 8 * level;

  /// Recorder bars: `4 + level*21*shape + 1.6*sin(…)`, clamped to 3..26.
  static double recorderBar(double level, double shape, double wobble) =>
      (4 + level * 21 * shape + 1.6 * wobble).clamp(3.0, 26.0);

  /// The bar shape of the reference: `0.42 + .58*|sin(phase + i*.52)|`.
  static double barShape(double phase, int index) =>
      0.42 + 0.58 * math.sin(phase + index * 0.52).abs();
}
