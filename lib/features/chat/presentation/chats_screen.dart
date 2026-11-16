import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/motion/pulse_motion.dart';
import '../../../core/motion/water_ripple.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/chat_controller.dart';
import '../domain/conversation.dart';
import 'widgets/chat_avatar.dart';
import 'widgets/empty_chats_art.dart';
import 'widgets/pulse_list_motion.dart';

/// Home = the real conversation list, not a placeholder (§4 A).
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final auth = ref.watch(authControllerProvider);
    final myId = auth is AuthSignedIn ? auth.user.id : '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brand600,
        foregroundColor: AppColors.onPrimary,
        onPressed: () => _openNewChatSheet(context, ref),
        icon: const Icon(Icons.chat_bubble_rounded, size: 18),
        label: const Text('New chat'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // The header stays put; only the list travels (as in the reference,
            // where the title and segments never move).
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                18,
                AppSpacing.screenX,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Messages', style: AppTypography.headlineMedium),
                  const SizedBox(height: 2),
                  Text('Chat · Call · Connect', style: AppTypography.caption),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(conversationsProvider.notifier).refresh(),
                child: PulseEdgeFade(
                  child: CustomScrollView(
                    slivers: [
                      conversations.when(
                        loading: () => const SliverFillRemaining(
                          hasScrollBody: false,
                          child: PulseLoading(message: 'Loading your chats'),
                        ),
                        error: (error, _) => SliverFillRemaining(
                          hasScrollBody: false,
                          child: ChatsErrorView(
                            failure: error is AppFailure
                                ? error
                                : const ServerFailure(),
                            onRetry: () => ref
                                .read(conversationsProvider.notifier)
                                .refresh(),
                          ),
                        ),
                        data: (items) {
                          if (items.isEmpty) {
                            return SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: EmptyChatsArt(
                                  onStartChat: () =>
                                      _openNewChatSheet(context, ref),
                                ),
                              ),
                            );
                          }
                          return SliverList.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: PulseMotion.rowGap),
                            itemBuilder: (context, i) => Padding(
                              padding: EdgeInsets.fromLTRB(
                                AppSpacing.screenX,
                                i == 0 ? PulseMotion.featherTop : 0,
                                AppSpacing.screenX,
                                i == items.length - 1 ? 90 : 0,
                              ),
                              child: ConversationTile(
                                conversation: items[i],
                                myId: myId,
                                index: i,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNewChatSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => const _NewChatSheet(),
    );
  }
}

/// One row of the inbox — the v4 card.
///
/// Layout, ink, radius, shadows, press/water feedback and the staggered
/// entrance all come from `pulse-home-reference-v4.html`; the numbers live in
/// [PulseMotion] and `docs/V4_MOTION_SPEC.md`.
///
/// Public so the layout can be widget-tested without standing up the screen.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.myId,
    this.index = 0,
  });

  final Conversation conversation;
  final String myId;

  /// Position in the list — drives the 26 ms entrance stagger.
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final time = c.lastMessageAt;
    final unread = c.unreadCount;
    final hasUnread = unread > 0;
    final mineLast = c.isMineLast(myId);
    final trimmed = c.lastMessagePreview?.trim();
    final hasPreview = trimmed != null && trimmed.isNotEmpty;

    // Second line, in priority order: the real preview, the group's size, an
    // invitation.
    final String line;
    if (hasPreview) {
      line = trimmed;
    } else if (c.isGroup) {
      line = '${c.subtitleLabel} · no messages yet';
    } else {
      line = 'Say hello';
    }

    final showTicks = mineLast && hasPreview;
    final spokenLine = showTicks ? 'You: $line' : line;

    return PulseRowMotion(
      index: index,
      seenKey: c.id,
      child: PulseTapSurface(
        onTap: () => context.push('/chat/${c.id}'),
        semanticsLabel:
            '${c.displayName}, '
            '${hasUnread ? '$unread unread, ' : ''}$spokenLine',
        child: Container(
          decoration: BoxDecoration(
            gradient: PulseMotion.rowSurface,
            borderRadius: BorderRadius.circular(PulseMotion.rowRadius),
            boxShadow: PulseMotion.rowShadow,
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(
            children: [
              _Avatar(c: c),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleMedium.copyWith(
                              color: PulseMotion.nameInk,
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (c.isGroup && c.memberCount > 0) ...[
                          const SizedBox(width: 6),
                          _Pill(
                            icon: Icons.groups_rounded,
                            text: '${c.memberCount}',
                          ),
                        ],
                        const Spacer(),
                        if (time != null)
                          Text(
                            _formatTime(time),
                            style: AppTypography.caption.copyWith(
                              color: hasUnread
                                  ? AppColors.brand600
                                  : AppColors.textMuted,
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                if (showTicks)
                                  const TextSpan(
                                    text: 'You: ',
                                    style: TextStyle(
                                      color: AppColors.brand600,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                TextSpan(text: line),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              color: hasUnread
                                  ? AppColors.textSecondary
                                  : PulseMotion.previewInk,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        // The ticks never get eaten by the ellipsis (v4 keeps
                        // the text in its own truncating box for this reason).
                        if (showTicks)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.done_all_rounded,
                              size: 15,
                              color: AppColors.brand500,
                            ),
                          ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: unread),
                        ],
                      ],
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

  static String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    if (day == today) return DateFormat.Hm().format(time);
    final diff = today.difference(day).inDays;
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEE').format(time);
    return DateFormat.MMMd().format(time);
  }
}

/// The avatar slot. The presence dot lives here (not inside [ChatAvatar]) so it
/// can sit on the right, stay a fixed 16 px and never inherit a scale.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.c});

  final Conversation c;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: PulseMotion.avatarSize,
      height: PulseMotion.avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ChatAvatar(
            label: c.initials,
            isGroup: c.isGroup,
            imageUrl: c.avatarUrl,
            size: PulseMotion.avatarSize,
          ),
          // No presence source yet — Phase F adds Supabase presence, so nothing
          // is drawn here rather than guessing "online".
        ],
      ),
    );
  }
}

/// A small count pill (group members, etc).
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.brand700),
          const SizedBox(width: 3),
          Text(
            text,
            style: AppTypography.micro.copyWith(
              color: AppColors.brand700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The unread counter: a brand circle for 1–99, "99+" beyond.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: AppTypography.micro.copyWith(
          color: AppColors.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _NewChatSheet extends ConsumerWidget {
  const _NewChatSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New chat', style: AppTypography.titleLarge),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/group/new');
                },
                icon: const Icon(Icons.group_add_rounded, size: 18),
                label: const Text('New group'),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick someone with a Pulse account.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: people.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => PulseInlineNotice(
                  message: error is AppFailure
                      ? error.userMessage
                      : 'Could not load people.',
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(peopleProvider),
                ),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No other accounts yet. Create a second account to test '
                          'chatting between two people.',
                          style: AppTypography.caption,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final person = list[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: ChatAvatar(
                              label: person.displayName.isEmpty
                                  ? '?'
                                  : person.displayName
                                        .substring(0, 1)
                                        .toUpperCase(),
                              isGroup: false,
                              imageUrl: person.avatarUrl,
                              size: 40,
                            ),
                            title: Text(
                              person.displayName,
                              style: AppTypography.titleMedium,
                            ),
                            subtitle: person.username == null
                                ? null
                                : Text(
                                    '@${person.username}',
                                    style: AppTypography.caption,
                                  ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textMuted,
                            ),
                            onTap: () async {
                              // Capture everything before the await: no BuildContext
                              // is touched after an async gap.
                              final navigator = Navigator.of(context);
                              final messenger = ScaffoldMessenger.of(context);
                              final router = GoRouter.of(context);
                              try {
                                final id = await ref.read(
                                  startConversationProvider(person.id).future,
                                );
                                navigator.pop();
                                router.push('/chat/$id');
                              } on AppFailure catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text(e.userMessage)),
                                );
                              }
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Failure state for the list: says what actually failed and offers the one
/// thing that can help (retry), instead of a dead-end "something went wrong".
class ChatsErrorView extends StatelessWidget {
  const ChatsErrorView({
    super.key,
    required this.failure,
    required this.onRetry,
  });

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = failure is NetworkFailure;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenX),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
                color: AppColors.brand600,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              offline ? 'You are offline' : "Couldn't load your chats",
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              offline
                  ? 'Check your connection — your saved messages are still here '
                        'inside each chat.'
                  : 'The server did not answer properly. Try again; if it keeps '
                        'happening, tell us what happened.',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(
              failure.userMessage,
              textAlign: TextAlign.center,
              style: AppTypography.micro.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand600,
                foregroundColor: AppColors.onPrimary,
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
