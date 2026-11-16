import 'package:material_ui/material_ui.dart';

import '../../domain/inbox_palette.dart';

/// The chat shell background: the reference's radial bloom at the top of a
/// three-stop vertical gradient. Painted once, never rebuilt.
class InboxBackdrop extends StatelessWidget {
  const InboxBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            InboxPalette.shellTop,
            InboxPalette.shellMid,
            InboxPalette.shellBottom,
          ],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          // radial-gradient(620px 320px at 50% -6%, #F7F3FE, transparent 62%)
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            height: 380,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.72),
                    radius: 1.05,
                    colors: [
                      InboxPalette.shellBloom,
                      InboxPalette.shellBloom.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
