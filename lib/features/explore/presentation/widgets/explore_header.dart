import 'package:material_ui/material_ui.dart';

import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import 'explore_pressable.dart';
import 'explore_search_bar.dart';

/// The three lines of the header, in the reference's order.
///
/// 1. `Explore` + the live "N new" pill + the filter button — where am I, and is
///    anything waiting for me.
/// 2. one contextual line: how the circle is doing right now, in real numbers.
/// 3. the search field with its own submit button — the only line that talks to
///    the server, and only when pressed.
class ExploreHeader extends StatelessWidget {
  const ExploreHeader({
    super.key,
    required this.pendingRequests,
    required this.friends,
    required this.searchController,
    required this.onSubmitSearch,
    required this.onOpenSearch,
    required this.onFilter,
  });

  final int pendingRequests;
  final int friends;
  final TextEditingController searchController;
  final ValueChanged<String> onSubmitSearch;
  final VoidCallback onOpenSearch;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (rect) =>
                    ExplorePalette.brand.createShader(rect),
                child: const Text(
                  'Explore',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.1,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (pendingRequests > 0) _LivePill(count: pendingRequests),
              const Spacer(),
              ExplorePressable(
                onTap: onFilter,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ExplorePalette.hairline),
                    boxShadow: ExplorePalette.field,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 19,
                    color: ExplorePalette.chipInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _subtitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: ExplorePalette.metaInk,
            ),
          ),
          const SizedBox(height: 12),
          ExploreSearchBar(
            controller: searchController,
            onSubmit: onSubmitSearch,
            readOnly: true,
            onTapField: onOpenSearch,
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    final circle = friends == 1
        ? '1 person in your circle'
        : '$friends in your circle';
    if (pendingRequests == 0) {
      return '$circle · all caught up';
    }
    final waiting = pendingRequests == 1
        ? '1 request waiting'
        : '$pendingRequests requests waiting';
    return '$waiting · $circle';
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F9EE),
        borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF17C653),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count new',
            style: const TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F8A46),
            ),
          ),
        ],
      ),
    );
  }
}
