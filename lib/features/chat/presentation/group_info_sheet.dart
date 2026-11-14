import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../application/chat_controller.dart';
import '../domain/chat_repository.dart';
import '../domain/conversation.dart';

/// Bottom sheet with the group's members and the actions my role allows.
/// Every action is re-checked by the server, the UI only hides what cannot work.
class GroupInfoSheet extends ConsumerWidget {
  const GroupInfoSheet({super.key, required this.conversation});

  final Conversation conversation;

  static Future<void> show(BuildContext context, Conversation conversation) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => GroupInfoSheet(conversation: conversation),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(groupMembersProvider(conversation.id));
    final auth = ref.watch(authControllerProvider);
    final myId = auth is AuthSignedIn ? auth.user.id : '';
    final me = members.value?.where((m) => m.userId == myId).firstOrNull;
    final role = me?.role ?? conversation.myRole;
    final canManage = role?.canManageMembers ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.displayName,
                        style: AppTypography.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        conversation.subtitleLabel,
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  IconButton(
                    tooltip: 'Rename group',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _rename(context, ref),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: members.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => PulseInlineNotice(
                  message: error is AppFailure
                      ? error.userMessage
                      : 'Could not load members.',
                  actionLabel: 'Retry',
                  onAction: () =>
                      ref.invalidate(groupMembersProvider(conversation.id)),
                ),
                data: (list) => ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final isMe = m.userId == myId;
                    final canAct =
                        !isMe &&
                        role != null &&
                        (role.isOwner ||
                            (role == GroupRole.admin &&
                                m.role == GroupRole.member));
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isMe ? '${m.displayName} (you)' : m.displayName,
                        style: AppTypography.titleMedium,
                      ),
                      subtitle: m.username == null
                          ? null
                          : Text(
                              '@${m.username}',
                              style: AppTypography.caption,
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m.role != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: m.role == GroupRole.member
                                    ? AppColors.bg
                                    : AppColors.brand600.withValues(
                                        alpha: 0.12,
                                      ),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                m.role!.label,
                                style: AppTypography.micro.copyWith(
                                  color: m.role == GroupRole.member
                                      ? AppColors.textMuted
                                      : AppColors.brand600,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          if (canAct)
                            PopupMenuButton<String>(
                              tooltip: 'Member actions',
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 20,
                              ),
                              onSelected: (value) =>
                                  _memberAction(context, ref, m, value, role),
                              itemBuilder: (_) => [
                                if (role.isOwner && m.role == GroupRole.member)
                                  const PopupMenuItem(
                                    value: 'promote',
                                    child: Text('Make admin'),
                                  ),
                                if (role.isOwner && m.role == GroupRole.admin)
                                  const PopupMenuItem(
                                    value: 'demote',
                                    child: Text('Make member'),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove from group'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            if (canManage) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _addMember(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('Add member'),
                ),
              ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _leave(context, ref),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Leave group'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _memberAction(
    BuildContext context,
    WidgetRef ref,
    GroupMember member,
    String action,
    GroupRole? myRole,
  ) async {
    final repo = ref.read(chatRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case 'promote':
          await repo.setGroupRole(
            conversation.id,
            member.userId,
            GroupRole.admin,
          );
        case 'demote':
          await repo.setGroupRole(
            conversation.id,
            member.userId,
            GroupRole.member,
          );
        case 'remove':
          await repo.removeGroupMember(conversation.id, member.userId);
      }
      ref.invalidate(groupMembersProvider(conversation.id));
      ref.invalidate(conversationsProvider);
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => const _AddMemberSheet(),
    );
    if (picked == null) return;
    final repo = ref.read(chatRepositoryProvider);
    try {
      await repo.addGroupMember(conversation.id, picked);
      ref.invalidate(groupMembersProvider(conversation.id));
      ref.invalidate(conversationsProvider);
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: conversation.displayName);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle == null || newTitle.length < 2) return;
    final repo = ref.read(chatRepositoryProvider);
    try {
      await repo.renameGroup(conversation.id, newTitle);
      ref.invalidate(conversationsProvider);
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Leave group?'),
        content: const Text(
          'You will stop receiving its messages. If you are the owner, an admin '
          'takes over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final repo = ref.read(chatRepositoryProvider);
    try {
      await repo.leaveGroup(conversation.id);
      ref.invalidate(conversationsProvider);
      navigator.pop();
      router.go('/app');
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }
}

class _AddMemberSheet extends ConsumerWidget {
  const _AddMemberSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add member', style: AppTypography.titleLarge),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: people.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) =>
                    const PulseInlineNotice(message: 'Could not load people.'),
                data: (list) => ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final person = list[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        person.displayName,
                        style: AppTypography.titleMedium,
                      ),
                      onTap: () => Navigator.of(context).pop(person.id),
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
