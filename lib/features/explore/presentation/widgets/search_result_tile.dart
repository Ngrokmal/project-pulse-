import 'package:material_ui/material_ui.dart';

import '../../application/friend_actions_controller.dart';
import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import '../../domain/friend_state.dart';
import '../../domain/people_search.dart';
import '../../domain/person.dart';
import 'explore_card_shell.dart';
import 'explore_pressable.dart';
import 'explore_pills.dart';
import 'friend_avatar.dart';
import 'match_meter.dart';
import 'sparkle_burst.dart';

/// One search result, in one of five states.
///
/// The row owns its state after a tap: the answer to "what did I just do" must
/// be visible immediately, not when a list refresh lands. Everything visual is
/// driven from [FriendState], so a button and a badge can never disagree.
class SearchResultTile extends StatefulWidget {
  const SearchResultTile({
    super.key,
    required this.hit,
    required this.actions,
    this.entranceDelay = Duration.zero,
  });

  final SearchHit hit;
  final FriendActions actions;
  final Duration entranceDelay;

  @override
  State<SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<SearchResultTile> {
  final SparkleController _sparkles = SparkleController();
  late FriendState _state = widget.hit.state;
  bool _sending = false;

  Person get _person => widget.hit.person;

  @override
  void dispose() {
    _sparkles.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_sending) return;
    setState(() => _sending = true);
    final started = DateTime.now();
    final result = await widget.actions.send(_person);

    // Hold the spinner for the reference's 620 ms: a spinner that blinks in and
    // out reads as a bug, a spinner that turns once reads as work.
    final elapsed = DateTime.now().difference(started);
    final remaining = ExploreMotion.requestSending - elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (result != null) _state = result;
    });
    if (_state == FriendState.friend) _sparkles.play();
  }

  Future<void> _cancel() async {
    if (_sending) return;
    setState(() => _sending = true);
    final ok = await widget.actions.cancelTo(_person);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _state = FriendState.none;
    });
  }

  Future<void> _accept() async {
    if (_sending) return;
    setState(() => _sending = true);
    _sparkles.play();
    final ok = await widget.actions.acceptFrom(_person);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _state = FriendState.friend;
    });
  }

  @override
  Widget build(BuildContext context) {
    final online = presenceIsOnline(_person);
    final badge = _state.badge;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: ExploreCardShell(
        state: _state,
        padding: const EdgeInsets.fromLTRB(11, 11, 11, 11),
        child: Row(
          children: [
            FriendAvatar(
              person: _person,
              size: 42,
              sparkles: _sparkles,
              ring: _state == FriendState.friend
                  ? FriendAvatarRing.friend
                  : FriendAvatarRing.none,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _person.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: ExplorePalette.ink,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        RelationBadge(
                          label: badge,
                          tint: _state == FriendState.requestedMe
                              ? ExplorePalette.badgeHotBg
                              : ExplorePalette.badgeMeBg,
                          ink: _state == FriendState.requestedMe
                              ? ExplorePalette.badgeHotInk
                              : ExplorePalette.brand700,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  ExploreMetaLine(
                    parts: <String>[
                      _person.atHandle,
                      if (_person.mutualCount > 0)
                        '${_person.mutualCount} mutual',
                      if (online) 'now',
                    ],
                    online: online,
                  ),
                  MatchMeter(score: widget.hit.score),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Action(
              state: _state,
              sending: _sending,
              onAdd: _add,
              onCancel: _cancel,
              onAccept: _accept,
              onMessage: () => widget.actions.message(_person),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.state,
    required this.sending,
    required this.onAdd,
    required this.onCancel,
    required this.onAccept,
    required this.onMessage,
  });

  final FriendState state;
  final bool sending;
  final VoidCallback onAdd;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      FriendState.self => const SizedBox.shrink(),
      FriendState.requestedByMe => RequestedPill(
        onTap: sending ? null : onCancel,
      ),
      FriendState.requestedMe => _AcceptButton(
        sending: sending,
        onTap: onAccept,
      ),
      FriendState.friend => _MessageButton(onTap: onMessage),
      FriendState.none => _AddButton(sending: sending, onTap: onAdd),
    };
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.sending, required this.onTap});

  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExplorePressable(
      onTap: sending ? null : onTap,
      child: Container(
        height: 33,
        width: 56,
        decoration: BoxDecoration(
          gradient: ExplorePalette.brand,
          borderRadius: BorderRadius.circular(11),
          boxShadow: ExplorePalette.primaryButton,
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: sending
              ? const SizedBox(
                  key: ValueKey<String>('spin'),
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'Add',
                  key: ValueKey<String>('label'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.sending, required this.onTap});

  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExplorePressable(
      onTap: sending ? null : onTap,
      child: Container(
        height: 33,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF3ED37C), Color(0xFF17A94D)],
          ),
          borderRadius: BorderRadius.circular(11),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x5917A94D),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          'Accept',
          style: TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _MessageButton extends StatelessWidget {
  const _MessageButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExplorePressable(
      onTap: onTap,
      child: Container(
        height: 33,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: ExplorePalette.online.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 13,
              color: ExplorePalette.friendInk,
            ),
            const SizedBox(width: 4),
            Text(
              'Message',
              style: const TextStyle(
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w800,
                color: ExplorePalette.friendInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
