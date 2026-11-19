import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../application/explore_counts.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import '../../domain/explore_section.dart';
import 'explore_pills.dart';

/// Requests · Sent · Friends — one control, a spring-driven pill, live counts.
///
/// The pill slides 520 ms on the overshoot curve and squishes for 220 ms, and a
/// count badge pops when it changes. LayoutBuilder measures once per build; the
/// pill itself is the only thing that animates.
class ExploreSegments extends StatelessWidget {
  const ExploreSegments({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final ExploreSection selected;
  final ExploreCounts counts;
  final ValueChanged<ExploreSection> onSelect;

  int _countFor(ExploreSection section) => switch (section) {
    ExploreSection.requests => counts.requests,
    ExploreSection.sent => counts.sent,
    ExploreSection.friends => counts.friends,
  };

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reducedMotion(context);
    final index = ExploreSection.values.indexOf(selected);

    return Container(
      height: ExploreMotion.segmentHeight,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFF1EDFB), Color(0xFFEAE5F8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x122A0E6B),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = (constraints.maxWidth - 8) / 3;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: reduce ? Duration.zero : ExploreMotion.segmentSlide,
                curve: ExploreMotion.spring,
                top: 4,
                bottom: 4,
                left: 4 + index * pillWidth,
                width: pillWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x2E2A0E6B),
                        blurRadius: 14,
                        offset: Offset(0, 7),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final section in ExploreSection.values)
                    Expanded(
                      child: _Segment(
                        label: section.label,
                        count: _countFor(section),
                        active: section == selected,
                        onTap: () => onSelect(section),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: '$label${count > 0 ? ', $count' : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                  color: active
                      ? ExplorePalette.brand700
                      : ExplorePalette.metaInk,
                ),
                child: Text(label),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                SegmentCount(value: count),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
