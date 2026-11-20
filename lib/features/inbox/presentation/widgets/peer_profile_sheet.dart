import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../chat/application/chat_controller.dart';
import '../../../chat/domain/chat_repository.dart';
import '../../../chat/domain/conversation.dart';
import '../../../presence/application/presence_controller.dart';
import '../../../profile/application/safety_controller.dart';
import '../../../profile/domain/safety_action.dart';
import '../../../presence/domain/presence.dart';
import '../../domain/inbox_motion.dart';
import '../../domain/inbox_palette.dart';
import 'inbox_entrance.dart';
import 'inbox_pressable.dart';

/// Counts for the profile card, read with `count: exact` on the server.
final conversationStatsProvider = FutureProvider.autoDispose
    .family<ConversationStats, String>((ref, conversationId) {
      return ref.watch(chatRepositoryProvider).stats(conversationId);
    });

/// The friend's profile card, exactly like the reference `p-sheet`:
/// the avatar arrives with its ring and orbiting sparks, then the name, the
/// presence line, the three actions and the three facts stagger in.
class PeerProfileSheet extends ConsumerStatefulWidget {
  const PeerProfileSheet({
    super.key,
    required this.conversation,
    required this.onCall,
    required this.onVideoCall,
    required this.onMessage,
  });

  final Conversation conversation;
  final VoidCallback onCall;
  final VoidCallback onVideoCall;
  final VoidCallback onMessage;

  static Future<void> show(
    BuildContext context, {
    required Conversation conversation,
    required VoidCallback onCall,
    required VoidCallback onVideoCall,
    required VoidCallback onMessage,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: const Color(0x6B140A34),
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 420),
        curve: InboxMotion.spring,
        reverseDuration: const Duration(milliseconds: 260),
        reverseCurve: Curves.easeInCubic,
      ),
      builder: (_) => PeerProfileSheet(
        conversation: conversation,
        onCall: onCall,
        onVideoCall: onVideoCall,
        onMessage: onMessage,
      ),
    );
  }

  @override
  ConsumerState<PeerProfileSheet> createState() => _PeerProfileSheetState();
}

class _PeerProfileSheetState extends ConsumerState<PeerProfileSheet> {
  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final peerId = conversation.isGroup ? '' : conversation.peer.id;
    final presence = peerId.isEmpty
        ? Presence.unknown
        : ref.watch(peerPresenceProvider(peerId)).value ?? Presence.unknown;
    final stats = peerId.isEmpty
        ? const AsyncValue<ConversationStats>.data(ConversationStats.empty)
        : ref.watch(conversationStatsProvider(conversation.id));
    final now = DateTime.now();
    final online = presence.isOnlineAt(now);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFFBFAFF)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Color(0x4D2A0E6B),
              blurRadius: 48,
              offset: Offset(0, -24),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1DDF0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              InboxEntrance(
                duration: const Duration(milliseconds: 700),
                slide: 14,
                scaleFrom: 0.5,
                blur: 0,
                child: _ProfileAvatar(
                  initials: conversation.initials,
                  seed: conversation.avatarUrl ?? conversation.id,
                  online: online,
                ),
              ),
              const SizedBox(height: 12),
              InboxEntrance(
                duration: const Duration(milliseconds: 500),
                delay: const Duration(milliseconds: 70),
                slide: 10,
                scaleFrom: 1,
                blur: 0,
                child: Text(
                  conversation.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17.5,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: InboxPalette.ink,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              InboxEntrance(
                duration: const Duration(milliseconds: 500),
                delay: const Duration(milliseconds: 110),
                slide: 10,
                scaleFrom: 1,
                blur: 0,
                child: Text(
                  conversation.isGroup
                      ? conversation.subtitleLabel
                      : presence.label(now),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: online ? AppColors.online : InboxPalette.muted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InboxEntrance(
                duration: const Duration(milliseconds: 520),
                delay: const Duration(milliseconds: 150),
                slide: 12,
                scaleFrom: 1,
                blur: 0,
                child: Row(
                  children: [
                    _Action(
                      icon: Icons.send_rounded,
                      label: 'Message',
                      onTap: () {
                        Navigator.of(context).maybePop();
                        widget.onMessage();
                      },
                    ),
                    const SizedBox(width: 8),
                    _Action(
                      icon: Icons.call_rounded,
                      label: 'Call',
                      onTap: () {
                        Navigator.of(context).maybePop();
                        widget.onCall();
                      },
                    ),
                    const SizedBox(width: 8),
                    _Action(
                      icon: Icons.videocam_rounded,
                      label: 'Video',
                      onTap: () {
                        Navigator.of(context).maybePop();
                        widget.onVideoCall();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              InboxEntrance(
                duration: const Duration(milliseconds: 540),
                delay: const Duration(milliseconds: 190),
                slide: 12,
                scaleFrom: 1,
                blur: 0,
                child: Column(
                  children: [
                    _FactRow(
                      label: 'Last seen',
                      value: conversation.isGroup
                          ? '—'
                          : presence.isKnown
                          ? _lastSeenValue(presence, now)
                          : 'not shared yet',
                    ),
                    _FactRow(
                      label: 'Messages',
                      value: switch (stats) {
                        AsyncData(:final value) => _count(value.messages),
                        _ => '…',
                      },
                    ),
                    _FactRow(
                      label: 'Media & files',
                      value: switch (stats) {
                        AsyncData(:final value) => _count(value.media),
                        _ => '…',
                      },
                    ),
                    if (peerId.isNotEmpty)
                      _SafetyRow(
                        peerId: peerId,
                        givenName: conversation.displayName
                            .split(RegExp(r'\s+'))
                            .first,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _count(int value) =>
      NumberFormat.decimalPattern().format(value);

  static String _lastSeenValue(Presence presence, DateTime now) {
    if (presence.isOnlineAt(now)) return 'just now';
    final seen = presence.lastSeenAt!;
    final today =
        seen.year == now.year && seen.month == now.month && seen.day == now.day;
    if (today) return DateFormat.Hm().format(seen);
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        seen.year == yesterday.year &&
        seen.month == yesterday.month &&
        seen.day == yesterday.day;
    if (isYesterday) return 'Yesterday at ${DateFormat.Hm().format(seen)}';
    return DateFormat('d MMM, HH:mm').format(seen);
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InboxPressable(
        onTap: onTap,
        pressedScale: 0.95,
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: InboxPalette.hairline),
            boxShadow: const [
              BoxShadow(
                color: Color(0x172A0E6B),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: AppColors.brand700),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: InboxPalette.hairline)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.3,
              fontWeight: FontWeight.w500,
              color: InboxPalette.muted,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B1A20),
            ),
          ),
        ],
      ),
    );
  }
}

/// 96 px avatar with the reference choreography: conic ring, two orbiting
/// sparks (7.5 s and 12 s reversed) and the presence dot on the corner.
class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({
    required this.initials,
    required this.seed,
    required this.online,
  });

  final String initials;
  final String seed;
  final bool online;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5600),
  )..repeat();
  late final AnimationController _orbitA = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7500),
  )..repeat();
  late final AnimationController _orbitB = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 12000),
  )..repeat();

  @override
  void dispose() {
    _ring.dispose();
    _orbitA.dispose();
    _orbitB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_ring, _orbitA, _orbitB]),
            builder: (context, child) => CustomPaint(
              size: const Size(132, 132),
              painter: _ProfileArtPainter(
                ringAngle: _ring.value * 2 * math.pi,
                orbitA: _orbitA.value * 2 * math.pi,
                orbitB: -_orbitB.value * 2 * math.pi,
                online: widget.online,
              ),
            ),
          ),
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: InboxPalette.avatarFor(widget.seed),
              borderRadius: BorderRadius.circular(30),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x664F25C4),
                  blurRadius: 34,
                  offset: Offset(0, 18),
                ),
                BoxShadow(
                  color: Color(0x66FFFFFF),
                  blurRadius: 0,
                  spreadRadius: 0,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: Text(
              widget.initials,
              style: const TextStyle(
                fontSize: 33,
                height: 1,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            right: 22,
            bottom: 26,
            child: _SheetPresenceDot(online: widget.online),
          ),
        ],
      ),
    );
  }
}

class _SheetPresenceDot extends StatefulWidget {
  const _SheetPresenceDot({required this.online});

  final bool online;

  @override
  State<_SheetPresenceDot> createState() => _SheetPresenceDotState();
}

class _SheetPresenceDotState extends State<_SheetPresenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: InboxMotion.presencePulse,
  );

  @override
  void initState() {
    super.initState();
    if (widget.online) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.online ? AppColors.online : InboxPalette.ghost;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = widget.online ? 0.35 + 0.5 * _pulse.value : 0.12;
        return Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFCFBFF), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: glow * 0.5),
                blurRadius: 0,
                spreadRadius: 1 + 4 * glow,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileArtPainter extends CustomPainter {
  const _ProfileArtPainter({
    required this.ringAngle,
    required this.orbitA,
    required this.orbitB,
    required this.online,
  });

  final double ringAngle;
  final double orbitA;
  final double orbitB;
  final bool online;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    // ---- the ring around the 96 px avatar: a soft halo pass, then one crisp
    // 2.4 px conic stroke. Nothing blurred on top of the stroke itself, so the
    // line reads sharp instead of smeared.
    final ringRect = Rect.fromCenter(center: center, width: 100, height: 100);
    final ringRRect = RRect.fromRectAndRadius(
      ringRect,
      const Radius.circular(32),
    );
    final sweep = SweepGradient(
      colors: const [
        InboxPalette.cyan,
        Color(0xFF7B5FED),
        Color(0xFFE1D9FC),
        InboxPalette.cyan,
      ],
      stops: const [0, 0.38, 0.62, 1],
      transform: GradientRotation(ringAngle),
    ).createShader(ringRect);

    canvas.drawRRect(
      ringRRect.inflate(2.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..shader = sweep
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      ringRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true
        ..shader = sweep,
    );

    // ---- orbit A: a cyan spark on a 118 px circle, tiny halo + sharp core.
    final sparkA =
        center + Offset(math.cos(orbitA) * 61, math.sin(orbitA) * 61);
    canvas.drawCircle(
      sparkA,
      6,
      Paint()
        ..color = InboxPalette.cyan.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    canvas.drawCircle(sparkA, 3.4, Paint()..color = InboxPalette.cyan);

    // ---- orbit B: a violet spark on a 134 px circle, reversed.
    final sparkB =
        center + Offset(math.cos(orbitB) * 67, math.sin(orbitB) * 67);
    canvas.drawCircle(
      sparkB,
      5,
      Paint()
        ..color = const Color(0xFFC7B6FF).withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(sparkB, 2.8, Paint()..color = const Color(0xFFC7B6FF));
  }

  @override
  bool shouldRepaint(_ProfileArtPainter oldDelegate) =>
      oldDelegate.ringAngle != ringAngle ||
      oldDelegate.orbitA != orbitA ||
      oldDelegate.orbitB != orbitB ||
      oldDelegate.online != online;
}

/// Clear · Block · Report for a real person.
///
/// These are the same three actions the profile card's Safety lens shows, and
/// they write for real: `cleared_at`, `public.blocks` (which the database then
/// enforces on both directions), and a `reports` row. A group has no single
/// person to block, so the row is never built for one.
class _SafetyRow extends ConsumerWidget {
  const _SafetyRow({required this.peerId, required this.givenName});

  final String peerId;
  final String givenName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(safetyControllerProvider);
    final busy = state.isBusy;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          _SafetyChip(
            icon: Icons.delete_outline_rounded,
            label: 'Clear chat',
            enabled: !busy,
            onTap: () => _confirm(context, ref, SafetyAction.clearChat),
          ),
          const SizedBox(width: 8),
          _SafetyChip(
            icon: Icons.block_rounded,
            label: 'Block',
            enabled: !busy,
            onTap: () => _confirm(context, ref, SafetyAction.block),
          ),
          const SizedBox(width: 8),
          _SafetyChip(
            icon: Icons.flag_outlined,
            label: busy && state.running == SafetyAction.report
                ? 'Sending'
                : 'Report',
            enabled: !busy,
            onTap: () => _report(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    SafetyAction action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action.titleFor(givenName)),
        content: Text(action.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action.confirmLabel),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final failure = await ref
        .read(safetyControllerProvider.notifier)
        .run(action, targetUserId: peerId);
    if (!context.mounted) return;
    _say(
      context,
      failure == null ? action.doneLabel : failure.userMessage,
    );
    if (failure == null) Navigator.of(context).maybePop();
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<ReportReason>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Why are you reporting this?'),
        children: [
          for (final reason in ReportReason.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(reason),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(reason.label),
              ),
            ),
        ],
      ),
    );
    if (reason == null || !context.mounted) return;
    final failure = await ref
        .read(safetyControllerProvider.notifier)
        .report(targetUserId: peerId, reason: reason);
    if (!context.mounted) return;
    _say(
      context,
      failure == null
          ? SafetyAction.report.doneLabel
          : failure.userMessage,
    );
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _SafetyChip extends StatelessWidget {
  const _SafetyChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InboxPressable(
        onTap: enabled ? onTap : null,
        pressedScale: 0.96,
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8F9),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFFBDDE1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: enabled ? AppColors.danger : InboxPalette.muted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: enabled ? AppColors.danger : InboxPalette.muted,
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
