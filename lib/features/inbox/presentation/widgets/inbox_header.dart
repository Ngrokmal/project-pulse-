import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/conversation.dart';
import '../../../presence/domain/presence.dart';
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
    required this.presence,
    required this.now,
    required this.onBack,
    required this.onProfile,
    required this.onCall,
    required this.onVideoCall,
    required this.onInfo,
  });

  final Conversation? conversation;
  final bool compact;
  final bool peerTyping;
  final bool offline;

  /// The peer's real presence (server `last_seen_at`), never a guess.
  final Presence presence;
  final DateTime now;
  final VoidCallback onBack;
  final VoidCallback? onProfile;
  final VoidCallback? onCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onInfo;

  String get _name => conversation?.displayName ?? 'Chat';

  String get _initials => conversation?.initials ?? '?';

  String get _seed => conversation?.avatarUrl ?? conversation?.id ?? _name;

  bool get _isGroup => conversation?.isGroup ?? false;

  bool get _online => !_isGroup && !peerTyping && presence.isOnlineAt(now);

  /// `online` in green, `last seen 5m ago` in muted, `typing` in brand — the
  /// reference's three states, all backed by data.
  String get _statusLabel {
    if (peerTyping) return 'typing';
    if (_isGroup) return conversation?.subtitleLabel ?? 'Group';
    if (offline) return 'offline — showing saved messages';
    return presence.label(now);
  }

  Color get _statusColor {
    if (peerTyping) return InboxPalette.brand600;
    if (offline) return InboxPalette.danger;
    if (_online) return AppColors.online;
    return InboxPalette.muted;
  }

  @override
  Widget build(BuildContext context) {
    final avatarPresence = peerTyping
        ? AvatarPresence.typing
        : _online || (conversation?.isGroup ?? false)
        ? AvatarPresence.active
        : AvatarPresence.offline;

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
            presence: avatarPresence,
            onTap: onProfile,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onProfile,
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
                    label: _statusLabel,
                    color: _statusColor,
                    typing: peerTyping,
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

/// Animated status line: the colour eases between green (online), violet
/// (typing) and muted (last seen), and the typing dots ride along.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.label,
    required this.color,
    required this.typing,
  });

  final String label;
  final Color color;
  final bool typing;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Row(
        key: ValueKey('$label-${typing ? 1 : 0}'),
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
          if (typing) ...[
            const SizedBox(width: 1),
            TypingDotsInline(color: color),
          ],
        ],
      ),
    );
  }
}
