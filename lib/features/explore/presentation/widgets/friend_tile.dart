import 'package:material_ui/material_ui.dart';

import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import '../../domain/person.dart';
import 'explore_pills.dart';
import 'explore_pressable.dart';
import 'friend_avatar.dart';
import 'row_entrance.dart';

/// One person in my circle.
///
/// Presence is the app's existing honesty rule: a green dot is only drawn while
/// the last heartbeat is inside the 90 s window, and the second line always
/// carries the words (`active now`, `last seen 5m ago`). A friend made in this
/// session says `just became friends` and wears a NEW chip for 2.6 s.
class FriendTile extends StatelessWidget {
  const FriendTile({
    super.key,
    required this.person,
    required this.onMessage,
    this.isNew = false,
    this.entranceDelay = Duration.zero,
  });

  final Person person;
  final VoidCallback onMessage;
  final bool isNew;
  final Duration entranceDelay;

  @override
  Widget build(BuildContext context) {
    final online = presenceIsOnline(person);
    final meta = isNew ? 'just became friends' : presenceLabel(person);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RowEntrance(
        delay: entranceDelay,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: ExplorePalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ExplorePalette.hairline),
            boxShadow: ExplorePalette.card,
          ),
          child: Row(
            children: [
              FriendAvatar(person: person, size: 44),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.1,
                              color: ExplorePalette.ink,
                            ),
                          ),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: 6),
                          const NewChip(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: online ? FontWeight.w700 : FontWeight.w600,
                        color: online
                            ? ExplorePalette.friendInk
                            : ExplorePalette.metaInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ExplorePressable(
                onTap: onMessage,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: ExplorePalette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ExplorePalette.hairline),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 17,
                    color: ExplorePalette.brand700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The whole-circle count, shown next to the Friends heading.
class FriendCountPill extends StatelessWidget {
  const FriendCountPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: ExploreMotion.press,
      child: Container(
        key: ValueKey<int>(count),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: ExplorePalette.brand500.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
        ),
        child: Text(
          '$count friend${count == 1 ? '' : 's'}',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            color: ExplorePalette.brand700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
