import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/chat_controller.dart';
import '../domain/conversation.dart';

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
        child: RefreshIndicator(
          onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenX,
                    18,
                    AppSpacing.screenX,
                    6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Messages', style: AppTypography.headlineMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Chat · Call · Connect',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ),
              conversations.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: PulseLoading(message: 'Loading your chats'),
                ),
                error: (error, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: PulseErrorState(
                    failure: error is AppFailure
                        ? error
                        : const ServerFailure(),
                    onRetry: () =>
                        ref.read(conversationsProvider.notifier).refresh(),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: PulseEmptyState(
                        icon: Icons.forum_outlined,
                        title: 'No conversations yet',
                        message:
                            'Start a chat with someone and it will appear here. '
                            'Messages are delivered instantly and stay readable offline.',
                        actionLabel: 'Start a chat',
                        onAction: () => _openNewChatSheet(context, ref),
                      ),
                    );
                  }
                  return SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.screenX,
                        0,
                        AppSpacing.screenX,
                        i == items.length - 1 ? 90 : 0,
                      ),
                      child: _ConversationTile(
                        conversation: items[i],
                        myId: myId,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
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

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.myId});

  final Conversation conversation;
  final String myId;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final time = c.lastMessageAt;
    return Material(
      color: AppColors.card,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        borderRadius: AppRadius.cardRadius,
        onTap: () => context.push('/chat/${c.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _Avatar(label: c.peer.initials),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.peer.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleMedium,
                          ),
                        ),
                        if (time != null)
                          Text(
                            _formatTime(time),
                            style: AppTypography.caption.copyWith(
                              color: c.hasUnread
                                  ? AppColors.brand600
                                  : AppColors.textMuted,
                              fontWeight: c.hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.lastMessagePreview == null
                          ? 'Say hello'
                          : '${c.isMineLast(myId) ? 'You: ' : ''}${c.lastMessagePreview}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption,
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
    if (today.difference(day).inDays == 1) return 'Yesterday';
    return DateFormat.MMMd().format(time);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, this.size = 46});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: AppTypography.titleMedium.copyWith(
          color: AppColors.onPrimary,
          fontWeight: FontWeight.w700,
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
                            leading: _Avatar(
                              label: person.displayName.isEmpty
                                  ? '?'
                                  : person.displayName
                                        .substring(0, 1)
                                        .toUpperCase(),
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
