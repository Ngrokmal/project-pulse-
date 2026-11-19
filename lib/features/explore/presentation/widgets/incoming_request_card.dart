import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import '../../domain/friend_request.dart';
import '../../domain/friend_state.dart';
import 'explore_card_shell.dart';
import 'explore_pressable.dart';
import 'friend_avatar.dart';
import 'row_entrance.dart';
import 'sparkle_burst.dart';
import 'swipe_decision_card.dart';

/// One incoming friend request: swipe it, or press a button.
///
/// Accept is a *moment*: the button turns green with a tick, a ring spins once
/// around the avatar, sparks leave it, and only then does the card collapse.
/// The server call starts on the tap — the animation never delays the decision.
class IncomingRequestCard extends StatefulWidget {
  const IncomingRequestCard({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onDecline,
    this.onCollapsed,
    this.entranceDelay = Duration.zero,
  });

  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// Called when the collapse is finished, so the list can drop the row without
  /// waiting for a refresh.
  final VoidCallback? onCollapsed;
  final Duration entranceDelay;

  @override
  State<IncomingRequestCard> createState() => _IncomingRequestCardState();
}

class _IncomingRequestCardState extends State<IncomingRequestCard>
    with TickerProviderStateMixin {
  final SparkleController _sparkles = SparkleController();

  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: ExploreMotion.acceptRing,
  );
  late final AnimationController _collapse = AnimationController(
    vsync: this,
    duration: ExploreMotion.cardCollapse,
  );

  bool _accepted = false;
  bool _leaving = false;

  @override
  void dispose() {
    _sparkles.dispose();
    _ring.dispose();
    _collapse.dispose();
    super.dispose();
  }

  void _accept() {
    if (_leaving) return;
    setState(() {
      _accepted = true;
      _leaving = true;
    });
    _sparkles.play();
    _ring.forward(from: 0);
    widget.onAccept();

    Future<void>.delayed(ExploreMotion.acceptMorph, () {
      if (!mounted) return;
      _collapse.forward().then((_) {
        if (mounted) widget.onCollapsed?.call();
      });
    });
  }

  void _decline() {
    if (_leaving) return;
    setState(() => _leaving = true);
    widget.onDecline();
    Future<void>.delayed(ExploreMotion.acceptMorph ~/ 2, () {
      if (!mounted) return;
      _collapse.forward().then((_) {
        if (mounted) widget.onCollapsed?.call();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.request.person;
    final reduce = AppMotion.reducedMotion(context);

    final card = ExploreCardShell(
      state: _accepted ? FriendState.friend : FriendState.none,
      padding: const EdgeInsets.fromLTRB(11, 11, 11, 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RingedAvatar(
                rotation: _ring,
                reduce: reduce,
                child: FriendAvatar(
                  person: person,
                  sparkles: _sparkles,
                  ring: _accepted
                      ? FriendAvatarRing.friend
                      : FriendAvatarRing.none,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.15,
                        color: ExplorePalette.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    ExploreMetaLine(
                      parts: <String>[
                        person.mutualCount > 0
                            ? '${person.mutualCount} mutual friend${person.mutualCount == 1 ? '' : 's'}'
                            : 'no mutual friends yet',
                        person.atHandle,
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _Ago.compact(DateTime.now().difference(widget.request.sentAt)),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: ExplorePalette.placeholder,
                  height: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: _AcceptButton(state: _accepted, onTap: _accept),
              ),
              const SizedBox(width: 8),
              if (!_accepted)
                SizedBox(
                  width: 104,
                  child: ExplorePressable(
                    onTap: _decline,
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F4FB),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: ExplorePalette.hairline),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Decline',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF7C7890),
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    final wrapped = Column(
      children: [
        SwipeDecisionCard(
          enabled: !_leaving,
          onAccept: _accept,
          onDecline: _decline,
          child: card,
        ),
        const SizedBox(height: 9),
      ],
    );

    if (reduce) {
      return SizeTransition(
        sizeFactor: ReverseAnimation(_collapse),
        alignment: Alignment.topCenter,
        child: wrapped,
      );
    }

    return SizeTransition(
      sizeFactor: ReverseAnimation(_collapse),
      alignment: Alignment.topCenter,
      child: RowEntrance(delay: widget.entranceDelay, child: wrapped),
    );
  }
}

class _RingedAvatar extends StatelessWidget {
  const _RingedAvatar({
    required this.child,
    required this.rotation,
    required this.reduce,
  });

  final Widget child;
  final Animation<double> rotation;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    if (reduce) return child;
    return AnimatedBuilder(
      animation: rotation,
      child: child,
      builder: (context, inner) {
        final t = rotation.value;
        // One turn, 950 ms, locked to the avatar box.
        return Transform.rotate(
          angle: t == 0 || t == 1 ? 0 : t * 6.28318,
          child: inner,
        );
      },
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.state, required this.onTap});

  final bool state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExplorePressable(
      onTap: state ? null : onTap,
      child: AnimatedContainer(
        duration: ExploreMotion.acceptMorph,
        curve: ExploreMotion.spring,
        height: 38,
        decoration: BoxDecoration(
          gradient: state
              ? const LinearGradient(
                  colors: <Color>[Color(0xFF3ED37C), Color(0xFF17A94D)],
                )
              : ExplorePalette.brand,
          borderRadius: BorderRadius.circular(13),
          boxShadow: state
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x5917A94D),
                    blurRadius: 16,
                    offset: Offset(0, 10),
                  ),
                ]
              : ExplorePalette.primaryButton,
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Row(
            key: ValueKey<bool>(state),
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state ? 'Friends' : 'Accept',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                  letterSpacing: 0.1,
                ),
              ),
              if (state) ...[
                const SizedBox(width: 5),
                const Icon(Icons.check_rounded, size: 15, color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `2m`, `18m`, `1h`, `3d` — the compact stamp the reference uses.
class _Ago {
  const _Ago._();

  static String compact(Duration age) {
    if (age.inMinutes < 1) return 'now';
    if (age.inMinutes < 60) return '${age.inMinutes}m';
    if (age.inHours < 24) return '${age.inHours}h';
    if (age.inDays < 7) return '${age.inDays}d';
    return '${(age.inDays / 7).floor()}w';
  }
}
