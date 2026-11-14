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
import '../../calls/application/call_controller.dart';
import '../../calls/domain/call_session.dart';
import '../domain/conversation.dart';
import '../application/chat_controller.dart';
import 'group_info_sheet.dart';
import '../../media/presentation/media_bubble.dart';
import '../../force_audio/presentation/force_audio_bubble.dart';
import '../../force_audio/presentation/force_audio_sheet.dart';
import '../../media/application/media_controller.dart';
import '../../media/data/file_picker_source.dart';
import '../../media/domain/media_asset.dart';
import '../domain/message.dart';

/// A single conversation. Real Realtime inserts, optimistic sends, offline retry.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await ref
          .read(chatThreadProvider(widget.conversationId).notifier)
          .send(text);
      _scrollToEnd();
    } on AppFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.userMessage)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Picks a file, validates it against the size limit for its type, uploads it
  /// with live progress and then sends the message that references it.
  Future<void> _attach() async {
    if (_sending) return;
    try {
      final media = await const FilePickerSource().pick();
      if (media == null) return; // cancelled
      final sizeError = PickedMedia.validateSize(
        media.resourceType,
        media.sizeBytes,
      );
      if (sizeError != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(sizeError)));
        return;
      }
      final kind = switch (media.resourceType) {
        MediaResourceType.image => MessageKind.image,
        MediaResourceType.video => MessageKind.video,
        MediaResourceType.raw => MessageKind.file,
      };
      setState(() => _sending = true);
      await ref
          .read(chatThreadProvider(widget.conversationId).notifier)
          .sendMedia(media: media, kind: kind);
      _scrollToEnd();
    } on AppFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.userMessage)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startCall(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
  ) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ref.read(
        startCallProvider((
          conversationId: conversation.id,
          kind: CallKind.audio,
        )).future,
      );
      router.push('/call/$id');
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(chatThreadProvider(widget.conversationId));
    final auth = ref.watch(authControllerProvider);
    final myId = auth is AuthSignedIn ? auth.user.id : '';
    // The peer name comes from the conversation list so this screen needs no
    // extra query.
    final conversation = ref
        .watch(conversationsProvider)
        .value
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/app'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conversation?.displayName ?? 'Chat',
              style: AppTypography.titleMedium,
            ),
            if (thread.value?.peerTyping == true)
              Text(
                'typing…',
                style: AppTypography.caption.copyWith(
                  color: AppColors.brand600,
                ),
              )
            else if (thread.value?.offline == true)
              Text(
                'offline — showing saved messages',
                style: AppTypography.caption.copyWith(color: AppColors.danger),
              )
            else if (conversation?.isGroup == true)
              Text(
                '${conversation!.subtitleLabel} · tap for details',
                style: AppTypography.caption,
              )
            else
              Text(
                conversation?.peer.username == null
                    ? 'Pulse'
                    : '@${conversation!.peer.username}',
                style: AppTypography.caption,
              ),
          ],
        ),
        actions: [
          if (conversation != null && !conversation.isGroup)
            IconButton(
              tooltip: 'Call',
              icon: const Icon(Icons.call_rounded, size: 20),
              onPressed: () => _startCall(context, ref, conversation),
            ),
          if (conversation?.isGroup == true)
            IconButton(
              tooltip: 'Group info',
              icon: const Icon(Icons.info_outline_rounded, size: 20),
              onPressed: () => GroupInfoSheet.show(context, conversation!),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: thread.when(
                loading: () => const PulseLoading(message: 'Opening chat'),
                error: (error, _) => PulseErrorState(
                  failure: error is AppFailure ? error : const ServerFailure(),
                  onRetry: () =>
                      ref.invalidate(chatThreadProvider(widget.conversationId)),
                ),
                data: (state) {
                  if (state.messages.isEmpty) {
                    return const PulseEmptyState(
                      icon: Icons.waving_hand_outlined,
                      title: 'Say hello',
                      message: 'This is the beginning of your conversation on Pulse.',
                    );
                  }
                  _scrollToEnd();
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    itemCount: state.messages.length,
                    itemBuilder: (context, i) {
                      final message = state.messages[i];
                      final previous = i == 0 ? null : state.messages[i - 1];
                      final showDay =
                          previous == null ||
                          !_sameDay(previous.createdAt, message.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDay) _DayDivider(when: message.createdAt),
                          _Bubble(
                            message: message,
                            mine: message.senderId == myId,
                            onRetry: () => ref
                                .read(
                                  chatThreadProvider(widget.conversationId)
                                      .notifier,
                                )
                                .retryFailed(),
                            onDelete: message.delivery == DeliveryState.sent
                                ? () => _confirmDelete(message)
                                : null,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            const _UploadProgressBar(),
            _Composer(
              controller: _controller,
              onAttach: _sending ? null : _attach,
              onForceAudio: _sending
                  ? null
                  : () => showForceAudioSheet(
                      context,
                      conversationId: widget.conversationId,
                    ),
              sending: _sending,
              onSend: _send,
              onTyping: () => ref
                  .read(chatThreadProvider(widget.conversationId).notifier)
                  .notifyTyping(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('It will be replaced with "Message deleted".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(chatThreadProvider(widget.conversationId).notifier)
          .deleteMessage(message);
    } on AppFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.when});

  final DateTime when;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final label = _ChatScreenState._sameDay(now, when)
        ? 'Today'
        : DateFormat.yMMMd().format(when);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.brand100,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(label, style: AppTypography.caption),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.onRetry,
    this.onDelete,
  });

  final Message message;
  final bool mine;
  final VoidCallback onRetry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final failed = message.delivery == DeliveryState.failed;
    final pending = message.delivery == DeliveryState.pending;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: mine && !failed ? AppColors.bubbleSelfGradient : null,
        color: mine
            ? (failed ? AppColors.danger.withValues(alpha: 0.12) : null)
            : AppColors.bubbleOther,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.bubble),
          topRight: const Radius.circular(AppRadius.bubble),
          bottomLeft: Radius.circular(mine ? AppRadius.bubble : 6),
          bottomRight: Radius.circular(mine ? 6 : AppRadius.bubble),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isDeleted && message.kind == MessageKind.forceAudio)
            ForceAudioBubble(
              messageId: message.id,
              mine: mine,
              durationMs: message.durationMs,
            )
          else if (!message.isDeleted &&
              message.kind != MessageKind.text &&
              message.mediaUrl != null)
            MediaBubble(message: message, mine: mine)
          else
            Text(
              message.isDeleted ? 'Message deleted' : (message.body ?? ''),
              style: AppTypography.bodyMedium.copyWith(
                color: mine && !failed
                    ? AppColors.onPrimary
                    : AppColors.textPrimary,
                fontStyle: message.isDeleted ? FontStyle.italic : null,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat.Hm().format(message.createdAt),
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  color: mine && !failed
                      ? AppColors.onPrimary.withValues(alpha: 0.7)
                      : AppColors.textMuted,
                ),
              ),
              if (pending) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 9,
                  height: 9,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: mine
                        ? AppColors.onPrimary.withValues(alpha: 0.8)
                        : AppColors.brand500,
                  ),
                ),
              ],
              if (failed) ...[
                const SizedBox(width: 6),
                Text(
                  'not sent',
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            GestureDetector(onLongPress: onDelete, child: bubble),
            if (failed)
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 13),
                label: Text(
                  'Tap to retry',
                  style: AppTypography.caption.copyWith(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadProgressBar extends ConsumerWidget {
  const _UploadProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(mediaUploadProvider);
    if (upload == null) return const SizedBox.shrink();
    final pct = (upload.progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 14,
                color: AppColors.brand600,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Uploading ${upload.fileName} — $pct%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: upload.progress,
              minHeight: 4,
              backgroundColor: AppColors.brand100,
              valueColor: const AlwaysStoppedAnimation(AppColors.brand600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onTyping,
    this.onAttach,
    this.onForceAudio,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback? onAttach;
  final VoidCallback? onForceAudio;
  final VoidCallback onSend;
  final VoidCallback onTyping;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Record a Force Audio',
            onPressed: onForceAudio,
            icon: const Icon(Icons.mic_rounded),
            color: AppColors.brand600,
          ),
          IconButton(
            tooltip: 'Attach a photo, video or file',
            onPressed: onAttach,
            icon: const Icon(Icons.attach_file_rounded),
            color: AppColors.brand600,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              maxLength: Message.bodyMax,
              buildCounter: (
                _, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
              onChanged: (_) => onTyping(),
              style: AppTypography.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Message',
                filled: true,
                fillColor: AppColors.inputFill,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: AppColors.onPrimary,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
