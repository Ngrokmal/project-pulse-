import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/profile_view_mode.dart';
import '../../domain/right_now.dart';

/// The grid, and the sentence underneath that explains it.
///
/// Every tile carries its own source caption. That is the whole point: the card
/// never shows a value without saying where the value came from, and the line
/// below the grid states what Pulse will *not* do to fill the gaps.
class RightNowGrid extends StatelessWidget {
  const RightNowGrid({
    super.key,
    required this.board,
    required this.mode,
    required this.onTap,
  });

  final RightNowBoard board;
  final ProfileViewMode mode;
  final ValueChanged<RightNowKind> onTap;

  @override
  Widget build(BuildContext context) {
    if (board.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two columns, in the order the domain produced them.
        LayoutBuilder(
          builder: (context, constraints) {
            final gap = constraints.maxWidth > 420 ? 12.0 : 10.0;
            final width = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final entry in board.entries)
                  SizedBox(
                    width: width,
                    child: _Tile(
                      entry: entry,
                      mode: mode,
                      onTap: () => onTap(entry.kind),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            RightNowBoard.disclaimer,
            style: AppTypography.micro.copyWith(
              fontSize: 11.5,
              height: 1.55,
              color: const Color(0xFFA9A5B8),
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile({required this.entry, required this.mode, required this.onTap});

  final RightNowEntry entry;
  final ProfileViewMode mode;
  final VoidCallback onTap;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _down = false;

  IconData get _icon => switch (widget.entry.kind) {
    RightNowKind.status => Icons.auto_awesome_rounded,
    RightNowKind.localTime => Icons.schedule_rounded,
    RightNowKind.where => Icons.place_outlined,
    RightNowKind.joined => Icons.star_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: AppMotion.fast,
        scale: _down ? 0.98 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: const Color(0xFFEDE9FA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEDE9FA)),
                ),
                child: Icon(_icon, size: 15, color: AppColors.brand600),
              ),
              const SizedBox(height: 10),
              Text(
                widget.entry.label.toUpperCase(),
                style: AppTypography.micro.copyWith(
                  fontSize: 10.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8C84A8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.entry.value,
                style: AppTypography.titleMedium.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                widget.entry.sourceFor(widget.mode),
                style: AppTypography.micro.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFFA9A5B8),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
