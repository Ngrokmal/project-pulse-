import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';

/// How much of the typed query survived, drawn as a hairline that grows.
///
/// Only visible below 100 %: an exact name does not need to prove it matched.
class MatchMeter extends StatelessWidget {
  const MatchMeter({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    if (score >= 100) return const SizedBox.shrink();
    final reduce = AppMotion.reducedMotion(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 70),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 3,
                  color: ExplorePalette.meterTrack,
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: score / 100),
                    duration: reduce
                        ? Duration.zero
                        : ExploreMotion.matchBarFill,
                    curve: ExploreMotion.easeOut,
                    builder: (context, value, _) => FractionallySizedBox(
                      widthFactor: value.clamp(0, 1),
                      child: Container(
                        height: 3,
                        decoration: const BoxDecoration(
                          gradient: ExplorePalette.meterFill,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$score% match',
            style: const TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.15,
              color: Color(0xFF9A93AF),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
