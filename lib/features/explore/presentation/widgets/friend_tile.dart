import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import '../../domain/person.dart';
import 'explore_pills.dart';
import 'explore_pressable.dart';
import 'friend_avatar.dart';
import 'row_entrance.dart';

/// One person in my circle.
///
/// The reference's row, lifted: a 50 px avatar with an honest presence dot that
/// breathes while it is green, the name with its state, a presence pill you can
/// read from across the room, the mutual count when there is one, and a filled
/// message button that opens the real conversation.
///
/// Presence is the app's existing rule — a dot only while the last heartbeat is
/// inside the 90 s window, and the words always say the same thing the dot does.
/// Everything animated here is one `AnimationController` per dot, wrapped in a
/// `RepaintBoundary`, and switched off under reduced motion.
class FriendTile extends StatelessWidget {
  const FriendTile({
    super.key,
    required this.person,
    required this.onMessage,
    this.isNew = false,
    this.busy = false,
    this.entranceDelay = Duration.zero,
  });

  final Person person;
  final VoidCallback onMessage;
  final bool isNew;

  /// The conversation is being created; the button shows a spinner instead of
  /// opening twice.
  final bool busy;
  final Duration entranceDelay;

  @override
  Widget build(BuildContext context) {
    final online = presenceIsOnline(person);
    final label = isNew ? 'just became friends' : presenceLabel(person);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RowEntrance(
        delay: entranceDelay,
        child: ExplorePressable(
          onTap: busy ? null : onMessage,
          scale: 0.985,
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFFFFFFFF), Color(0xFFFBFAFF)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: online
                    ? ExplorePalette.friendBorder
                    : ExplorePalette.hairline,
              ),
              boxShadow: ExplorePalette.card,
            ),
            child: Row(
              children: [
                FriendAvatar(person: person, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              person.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.25,
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
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Flexible(
                            child: _PresencePill(
                              label: label,
                              online: online,
                              fresh: isNew,
                            ),
                          ),
                          if (person.mutualCount > 0) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: _MutualChip(count: person.mutualCount),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _MessageButton(busy: busy, onTap: onMessage),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `active now` / `last seen 5m ago` as a pill, with a dot that breathes only
/// while it is actually green.
class _PresencePill extends StatelessWidget {
  const _PresencePill({
    required this.label,
    required this.online,
    required this.fresh,
  });

  final String label;
  final bool online;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final tint = fresh
        ? ExplorePalette.badgeFriendBg
        : (online ? ExplorePalette.badgeFriendBg : const Color(0xFFF4F2FA));
    final ink = fresh
        ? ExplorePalette.friendInk
        : (online ? ExplorePalette.friendInk : ExplorePalette.metaInk);

    return AnimatedContainer(
      duration: ExploreMotion.press,
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (online || fresh)
            _LiveDot(color: ink)
          else
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: ExplorePalette.placeholder,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.05,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: ExploreMotion.liveDotPulse,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 5.5,
      height: 5.5,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );

    if (AppMotion.reducedMotion(context)) return dot;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = Curves.easeInOutSine.transform(_pulse.value);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                child: Container(
                  width: 5.5 + t * 7,
                  height: 5.5 + t * 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.22 * (1 - t)),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: dot,
      ),
    );
  }
}

class _MutualChip extends StatelessWidget {
  const _MutualChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: ExplorePalette.brand500.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.people_alt_rounded,
            size: 10,
            color: ExplorePalette.brand500,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$count mutual',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1,
                fontWeight: FontWeight.w800,
                color: ExplorePalette.brand700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The filled message button. 44 px, brand gradient, its own shadow, and a press
/// that squishes to 0.9 — the same gesture language as the search button.
class _MessageButton extends StatelessWidget {
  const _MessageButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Message',
      child: ExplorePressable(
        onTap: busy ? null : onTap,
        scale: 0.9,
        child: AnimatedContainer(
          duration: ExploreMotion.press,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: ExplorePalette.brand,
            borderRadius: BorderRadius.circular(15),
            // Slightly tighter than the primary button's glow: the CTA sits
            // 11 px from the card's edge and its halo must not spill past it.
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x4D5F3FDC),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: busy
                ? const SizedBox(
                    key: ValueKey<String>('busy'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(
                    Icons.chat_bubble_rounded,
                    key: ValueKey<String>('idle'),
                    size: 19,
                    color: Colors.white,
                  ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              ExplorePalette.brand500.withValues(alpha: 0.14),
              ExplorePalette.brand500.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(ExploreMotion.pillRadius),
          border: Border.all(
            color: ExplorePalette.brand500.withValues(alpha: 0.18),
          ),
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
