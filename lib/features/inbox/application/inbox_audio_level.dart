import 'package:flutter/foundation.dart';

/// The one live value that drives every voiced motion in the inbox.
///
/// The reference sets a single `--lvl` custom property on the composer and every
/// animation reads it. This class is that property: one object, one
/// `notifyListeners()` per frame, and every painter/widget repaints from it.
/// Painting is driven through `CustomPainter(repaint: level)`, so the widget
/// tree is **not** rebuilt per frame — only the layers that read the level.
class InboxAudioLevel extends ChangeNotifier {
  double _value = 0;
  double _target = 0;
  double _time = 0;

  /// Smoothed 0..1 level (reference: `level += (raw - level) * .32`).
  double get value => _value;

  /// Monotonic seconds since the recorder started — the phase source for the
  /// bar shape and the letter wave.
  double get time => _time;

  bool get isSilent => _value <= 0.001 && _target <= 0.001;

  /// A new raw sample from the microphone (or 0 when nothing is recording).
  void setTarget(double raw) {
    _target = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;
  }

  /// Advances one frame: smooths towards the target and notifies once.
  void advance(double dt) {
    _time += dt;
    _value += (_target - _value) * 0.32;
    if (_value < 0.0005) _value = 0;
    notifyListeners();
  }

  /// Silences everything without stopping the clock (pause / discard).
  void silence() {
    _target = 0;
    _value = 0;
    notifyListeners();
  }

  void reset() {
    _target = 0;
    _value = 0;
    _time = 0;
    notifyListeners();
  }
}
