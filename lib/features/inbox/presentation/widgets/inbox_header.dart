import 'package:material_ui/material_ui.dart';

import '../../../chat/domain/conversation.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';
import 'inbox_avatar.dart';
import 'inbox_pressable.dart';
import 'typing_dots_inline.dart';

/// The chat header: back, the choreographed avatar, name + live status line and
/// the call actions. It compacts (12/10 → 6/6 padding + shadow) as soon as the
/// thread is scrolled, exactly like the reference.
class InboxHeader extends StatelessWidget {
  const InboxHeader({
    super.key,
    required this.conversation,
    required this.compact,
    required this.peerTyping,
    required this.offline,
    required this.onBack,
    required this.onCall,
    required this.onVideoCall,
    required this.onInfo,
  });

  final Conversation? conversation;
  final bool compact;
  final bool peerTyping;
  final bool offline;
  final VoidCallback onBack;
  final VoidCallback? onCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onInfo;

  String get _name => conversation?.displayName ?? 'Chat';

  String get _initials => conversation?.initials ?? '?';

  String get _seed => conversation?.avatarUrl ?? conversation?.id ?? _name;

  bool get _isGroup => conversation?.isGroup ?? false;

  @override
  Widget build(BuildContext context) {
    final presence = peerTyping
        ? AvatarPresence.typing
        : offline
        ? AvatarPresence.offline
        : AvatarPresence.active;

    return AnimatedContainer(
      duration: InboxMotion.headerCompact,
      curve: InboxMotion.easeOut,
      padding: EdgeInsets.fromLTRB(6, compact ? 6 : 12, 8, compact ? 6 : 10),
      decoration: BoxDecoration(
        color: InboxPalette.headerFill,
        border: Border(
          bottom: BorderSide(
            color: InboxPalette.hairline.withValues(alpha: 0.9),
          ),
        ),
        boxShadow: compact
            ? const [
                BoxShadow(
                  color: Color(0x172A0E6B),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          InboxPressable(
            onTap: onBack,
            semanticLabel: 'Back',
            pressedScale: 0.9,
            child: const SizedBox(
              width: 38,
              height: 38,
              child: Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            ),
          ),
          const SizedBox(width: 4),
          InboxAvatar(
            initials: _initials,
            seed: _seed,
            presence: presence,
            onTap: onInfo,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onInfo,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.25,
                      color: InboxPalette.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  _StatusLine(
                    peerTyping: peerTyping,
                    offline: offline,
                    isGroup: _isGroup,
                    subtitle: conversation?.subtitleLabel ?? 'on Pulse',
                  ),
                ],
              ),
            ),
          ),
          if (onCall != null)
            InboxPressable(
              onTap: onCall,
              semanticLabel: 'Call',
              child: const SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  Icons.call_rounded,
                  size: 20,
                  color: InboxPalette.ink,
                ),
              ),
            ),
          if (onVideoCall != null)
            InboxPressable(
              onTap: onVideoCall,
              semanticLabel: 'Video call',
              child: const SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  Icons.videocam_rounded,
                  size: 21,
                  color: InboxPalette.ink,
                ),
              ),
            ),
          if (onInfo != null && (onCall == null && onVideoCall == null))
            InboxPressable(
              onTap: onInfo,
              semanticLabel: 'Details',
              child: const SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: InboxPalette.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Animated status line: colour eases between online-green, typing-violet and
/// muted, and the typing dots ride along (reference `typeDot`).
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.peerTyping,
    required this.offline,
    required this.isGroup,
    required this.subtitle,
  });

  final bool peerTyping;
  final bool offline;
  final bool isGroup;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final color = peerTyping
        ? InboxPalette.brand600
        : offline
        ? InboxPalette.muted
        : InboxPalette.brand500;

    final label = peerTyping
        ? 'typing'
        : offline
        ? 'offline — showing saved messages'
        : isGroup
        ? subtitle
        : subtitle;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Row(
        key: ValueKey('$label-${peerTyping ? 1 : 0}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (peerTyping) ...[
            const SizedBox(width: 1),
            TypingDotsInline(color: color),
          ],
        ],
      ),
    );
  }
}
