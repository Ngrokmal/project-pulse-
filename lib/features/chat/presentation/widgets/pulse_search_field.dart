import 'dart:ui' as ui show Gradient;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import '../../../../core/motion/pulse_icons.dart';
import '../../../../core/motion/pulse_motion.dart';
import '../../../../core/theme/app_colors.dart';
import 'pulse_brand.dart';

/// The search field, exactly as the reference opens it: the wrapper unfolds
/// from zero height, tips in from the top-right, and its icon, text and close
/// button arrive 50 ms apart.
class PulseSearchField extends StatelessWidget {
  const PulseSearchField({
    super.key,
    required this.t,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  /// 0 → closed, 1 → open, over [PulseMotion.searchOpen].
  final Animation<double> t;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  Animation<double> _seq(double delayMs, {Curve curve = PulseMotion.spring}) {
    final total = PulseMotion.searchOpen.inMilliseconds;
    return CurvedAnimation(
      parent: t,
      curve: Interval((delayMs / total).clamp(0.0, 1.0), 1, curve: curve),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wrap = CurvedAnimation(parent: t, curve: PulseMotion.spring);
    final icon = _seq(100);
    final field = _seq(150);
    final close = _seq(210);

    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final open = t.value;
        if (open <= 0.001) return const SizedBox(width: double.infinity);

        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: open,
            child: Transform.translate(
              offset: Offset(0, -8 * (1 - wrap.value)),
              child: Transform.scale(
                scale: 0.92 + 0.08 * wrap.value,
                alignment: Alignment.topRight,
                child: Opacity(
                  opacity: open.clamp(0.0, 1.0),
                  child: SizedBox(
                    height: 58,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.only(left: 15, right: 7),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2A0E6B)
                                  .withValues(alpha: 0.32),
                              offset: const Offset(0, 18),
                              blurRadius: 34,
                              spreadRadius: -24,
                            ),
                            BoxShadow(
                              color: const Color(0xFF2A0E6B)
                                  .withValues(alpha: 0.04),
                              offset: const Offset(0, 2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // The purple bloom that lights up inside the field.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: open,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: CustomPaint(
                                      painter: _BloomPainter(
                                        color: AppColors.brand500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                _slideIn(
                                  icon,
                                  const PulseIcon(
                                    paths: PulseIcons.search,
                                    size: 18,
                                    color: Color(0xFF9B98AC),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _slideIn(
                                    field,
                                    TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      onChanged: onChanged,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        color: Color(0xFF151418),
                                        fontFamily: 'Roboto',
                                      ),
                                      cursorColor: AppColors.brand600,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        focusedErrorBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.zero,
                                        hintText: 'Search messages or people',
                                        hintStyle: TextStyle(
                                          fontSize: 14.5,
                                          color: Color(0xFFA9A7B4),
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                _slideIn(
                                  close,
                                  PulseIconButton(
                                    label: 'Close search',
                                    size: 28,
                                    onPressed: onClose,
                                    icon: const PulseIcon(
                                      paths: PulseIcons.close,
                                      size: 16,
                                      color: Color(0xFF9B98AC),
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _slideIn(Animation<double> anim, Widget child) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(-10 * (1 - anim.value), 0),
          child: child,
        ),
      ),
    );
  }
}

/// The header itself: brand on the left, actions on the right, and the whole
/// bar folding away (with the brand sliding out to the left and the actions to
/// the right, both blurring) when search takes over.
class PulseAppBar extends StatelessWidget {
  const PulseAppBar({
    super.key,
    required this.t,
    required this.onSearch,
    required this.onBell,
    this.noticeCount = 0,
  });

  /// 0 → at rest, 1 → folded away.
  final Animation<double> t;
  final VoidCallback onSearch;
  final VoidCallback onBell;
  final int noticeCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value;
        if (v >= 0.999) return const SizedBox(width: double.infinity);

        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1 - v,
            child: Opacity(
              opacity: 1 - v,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 6 - 6 * v,
                  bottom: 8 - 8 * v,
                ),
                child: Row(
                  children: [
                    _blurred(
                      3 * v,
                      Transform.translate(
                        offset: Offset(-20 * v, 0),
                        child: Transform.scale(
                          scale: 1 - 0.12 * v,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              PulseLogo(),
                              SizedBox(width: 11),
                              PulseWordmark(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    _blurred(
                      2 * v,
                      Transform.translate(
                        offset: Offset(16 * v, 0),
                        child: Transform.scale(
                          scale: 1 - 0.14 * v,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PulseIconButton(
                                label: 'Search messages',
                                onPressed: onSearch,
                                icon: const PulseIcon(
                                  paths: PulseIcons.search,
                                  size: 23,
                                  color: Color(0xFF141452),
                                ),
                              ),
                              const SizedBox(width: 6),
                              PulseIconButton(
                                label: noticeCount > 0
                                    ? 'Notifications, $noticeCount unread'
                                    : 'Notifications',
                                onPressed: onBell,
                                badgeCount: noticeCount,
                                wiggle: true,
                                icon: const PulseIcon(
                                  paths: PulseIcons.bell,
                                  size: 24,
                                  color: Color(0xFF141452),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _blurred(double px, Widget child) {
    if (px <= 0.01) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: px / 2, sigmaY: px / 2),
      child: child,
    );
  }
}

/// `radial-gradient(150% 200% at 8% 50%, rgba(123,95,237,.20), rgba(123,95,237,0) 60%)`
///
/// Drawn by hand because Flutter's [RadialGradient] is circular unless you hand
/// it a transform — and the whole point of the reference's bloom is that it is a
/// wide ellipse hugging the left edge, so the field reads lavender on the left
/// and white on the right.
class _BloomPainter extends CustomPainter {
  _BloomPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rx = size.width * 1.5;
    final ry = size.height * 2.0;

    // A radial gradient with equal radii, stretched into the ellipse.
    final matrix = Matrix4.identity()
      ..translateByDouble(size.width * 0.08, size.height * 0.5, 0, 1)
      ..scaleByDouble(1.0, ry / rx, 1.0, 1.0)
      ..translateByDouble(-size.width * 0.08, -size.height * 0.5, 0, 1);

    final shader = ui.Gradient.radial(
      Offset(size.width * 0.08, size.height * 0.5),
      rx,
      [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
      const [0.0, 0.6],
      TileMode.clamp,
      matrix.storage,
    );

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_BloomPainter old) => old.color != color;
}
