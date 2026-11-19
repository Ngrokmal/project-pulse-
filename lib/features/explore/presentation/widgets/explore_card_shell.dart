import 'package:material_ui/material_ui.dart';

import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import '../../domain/friend_state.dart';

/// The white card every Explore row sits on.
///
/// One decoration, one place: the border and the tint are the only things a
/// relation state changes, and they change through `AnimatedContainer`, so a row
/// turning green takes 300 ms instead of a jump cut.
class ExploreCardShell extends StatelessWidget {
  const ExploreCardShell({
    super.key,
    required this.child,
    this.state = FriendState.none,
    this.padding = const EdgeInsets.fromLTRB(11, 11, 11, 11),
  });

  final Widget child;
  final FriendState state;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final (border, tint) = switch (state) {
      FriendState.requestedByMe => (
        ExplorePalette.requestedBorder,
        ExplorePalette.requestedTint,
      ),
      FriendState.requestedMe => (
        ExplorePalette.incomingBorder,
        ExplorePalette.incomingTint,
      ),
      FriendState.friend => (
        ExplorePalette.friendBorder,
        ExplorePalette.friendTint,
      ),
      _ => (ExplorePalette.hairline, ExplorePalette.surface),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: ExploreMotion.easeOut,
      padding: padding,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(ExploreMotion.cardRadius),
        border: Border.all(color: border),
        boxShadow: ExplorePalette.card,
      ),
      child: child,
    );
  }
}

/// `3 mutual friends · @ayesha.r` — one line, ellipsised, never wrapped.
class ExploreMetaLine extends StatelessWidget {
  const ExploreMetaLine({super.key, required this.parts, this.online = false});

  final List<String> parts;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final visible = parts.where((p) => p.isNotEmpty).toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return Text(
      visible.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.05,
        color: online ? ExplorePalette.friendInk : ExplorePalette.metaInk,
      ),
    );
  }
}
