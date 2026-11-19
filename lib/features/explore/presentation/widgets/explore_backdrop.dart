import 'package:material_ui/material_ui.dart';

import '../../domain/explore_palette.dart';

/// The shell behind Explore: three stops of the reference gradient plus one soft
/// violet bloom at the top.
///
/// Purely decorative, `const`, and never rebuilt — no blur filter, because a
/// `BackdropFilter` here would cost a full-screen readback every frame on a
/// low-end phone for a difference nobody can see.
class ExploreBackdrop extends StatelessWidget {
  const ExploreBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            ExplorePalette.shellTop,
            ExplorePalette.shellMid,
            ExplorePalette.shellBottom,
          ],
          stops: <double>[0, 0.38, 1],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}
