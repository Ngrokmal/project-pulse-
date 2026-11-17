import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../calls/application/call_controller.dart';
import '../../calls/domain/call_session.dart';
import '../../chat/application/chat_controller.dart';
import '../../chat/domain/conversation.dart';
import '../../chat/domain/message.dart';
import '../../chat/presentation/group_info_sheet.dart';
import '../../force_audio/presentation/force_audio_sheet.dart';
import '../../media/data/file_picker_source.dart';
import '../../media/domain/media_asset.dart';
import '../../presence/application/presence_controller.dart';
import '../../presence/domain/presence.dart';
import '../../profile/application/profile_controller.dart';
import '../application/voice_playback_controller.dart';
import '../application/voice_recording_controller.dart';
import '../domain/inbox_palette.dart';
import '../domain/inbox_timeline.dart';
import 'widgets/attach_popover.dart';
import 'widgets/composer_bar.dart';
import 'widgets/inbox_backdrop.dart';
import 'widgets/inbox_empty_state.dart';
import 'widgets/inbox_header.dart';
import 'widgets/inbox_thread.dart';
import 'widgets/jump_to_latest.dart';
import 'widgets/offline_bar.dart';
import 'widgets/peer_profile_sheet.dart';
import 'widgets/upload_progress_bar.dart';

/// The personal inbox — one conversation, rebuilt from
/// `pulse-inbox-reference-v3.html`.
///
/// This screen owns layout and gesture routing only: timeline grouping lives in
/// `domain/inbox_timeline.dart`, the level in `application/inbox_audio_level.dart`,
/// playback in `application/voice_playback_controller.dart`, recording in
/// `application/voice_recording_controller.dart`, and every visual with a
/// per-frame animation in its own painter widget.
class PersonalInboxScreen extends ConsumerStatefulWidget {
  const PersonalInboxScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<PersonalInboxScreen> createState() =>
      _PersonalInboxScreenState();
}

class _PersonalInboxScreenState extends ConsumerState<PersonalInboxScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _compact = false;
  bool _atBottom = true;
  bool _attachOpen = false;
  int _unseen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _input.dispose();
    _focus.dispose();
    // Leaving the screen must never leave a hot microphone or a playing clip.
    try {
      ref.read(voiceRecordingProvider.notifier).discard();
      ref.read(voicePlaybackProvider.notifier).stop();
    } on Object catch (_) {
      // The providers may already be disposed with the route.
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pixels = _scroll.position.pixels;
    final atBottom = pixels <= 24;
    final compact = pixels > 12;
    if (atBottom == _atBottom && compact == _compact) return;
    setState(() {
      _atBottom = atBottom;
      _compact = compact;
      if (atBottom) _unseen = 0;
    });
  }

  void _scrollToLatest({bool animate = true}) {
    if (!_scroll.hasClients) return;
    if (animate) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(0);
    }
  }

  Future<void> _sendText() async {
    final chat = ref.read(chatThreadProvider(widget.conversationId).notifier);
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _attachOpen = false;
    try {
      await chat.send(text);
      _scrollToLatest();
    } on AppFailure catch (failure) {
      // Never eat a draft: put the text back where the user left it.
      _input.text = text;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.userMessage)));
      }
    }
  }

  Future<String?> _sendVoice() async {
    final error = await ref
        .read(voiceRecordingProvider.notifier)
        .send(conversationId: widget.conversationId);
    if (error == null) _scrollToLatest();
    return error;
  }

  Future<void> _pick({required bool imagesOnly}) async {
    if (_attachOpen) setState(() => _attachOpen = false);
    try {
      const picker = FilePickerSource();
      final media = imagesOnly
          ? await picker.pickImage()
          : await picker.pickAny();
      if (media == null) return;
      final sizeError = PickedMedia.validateSize(
        media.resourceType,
        media.sizeBytes,
      );
      if (sizeError != null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(sizeError)));
        }
        return;
      }
      final kind = switch (media.resourceType) {
        MediaResourceType.image => MessageKind.image,
        MediaResourceType.video => MessageKind.video,
        MediaResourceType.raw => MessageKind.file,
      };
      await ref
          .read(chatThreadProvider(widget.conversationId).notifier)
          .sendMedia(media: media, kind: kind);
      _scrollToLatest();
    } on AppFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.userMessage)));
      }
    }
  }

  void _openForceAudio() {
    setState(() => _attachOpen = false);
    showForceAudioSheet(context, conversationId: widget.conversationId);
  }

  /// Tapping the avatar or the name opens the friend's profile card (v3's
  /// `p-sheet`) — the same card for both entry points.
  void _openProfile(Conversation conversation) {
    PeerProfileSheet.show(
      context,
      conversation: conversation,
      onMessage: () => _focus.requestFocus(),
      onCall: () => _startCall(conversation, CallKind.audio),
      onVideoCall: () => _startCall(conversation, CallKind.video),
    );
  }

  Future<void> _startCall(Conversation conversation, CallKind kind) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final id = await ref.read(
        startCallProvider((conversationId: conversation.id, kind: kind)).future,
      );
      router.push('/call/$id');
    } on AppFailure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.userMessage)));
    }
  }

  Future<void> _confirmDelete(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('It will be removed for everyone in this chat.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
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
    } on AppFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.userMessage)));
    }
  }

  void _onSuggestion(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(chatThreadProvider(widget.conversationId));
    final conversations = ref.watch(conversationsProvider).value;
    final conversation = conversations
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final auth = ref.watch(authControllerProvider);
    final myId = auth is AuthSignedIn ? auth.user.id : '';
    final state = thread.value;
    final messages = state?.messages ?? const <Message>[];
    final isGroup = conversation?.isGroup ?? false;

    // Group read receipts are not a single cursor, so `seen` is only claimed for
    // direct chats where the peer's last_read_at really means "read it".
    final cells = buildInboxTimeline(
      messages,
      myId: myId,
      peerLastReadAt: isGroup ? null : conversation?.peerLastReadAt,
    );

    // Realtime arrivals: follow them when the user is at the bottom, count them
    // when they are reading history.
    ref.listen(
      chatThreadProvider(widget.conversationId)
          .select((value) => value.value?.messages.length ?? 0),
      (previous, next) {
        if (next <= (previous ?? 0)) return;
        final added = next - (previous ?? 0);
        if (_atBottom) {
          _scrollToLatest();
        } else {
          setState(() => _unseen += added);
        }
      },
    );

    final canCall = conversation != null && !isGroup;

    // Presence is read, never guessed: the provider polls `user_presence` while
    // this screen is alive, and the label is derived at build time.
    final peerId = conversation != null && !isGroup ? conversation.peer.id : '';
    final presence = peerId.isEmpty
        ? Presence.unknown
        : ref.watch(peerPresenceProvider(peerId)).value ?? Presence.unknown;
    final now = DateTime.now();
    final myName =
        ref.watch(profileControllerProvider).value?.displayName ??
        (ref.watch(authControllerProvider) is AuthSignedIn
            ? (ref.watch(
                authControllerProvider,
              ) as AuthSignedIn).user.displayName
            : null);

    return Scaffold(
      backgroundColor: InboxPalette.shellMid,
      body: InboxBackdrop(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  InboxHeader(
                    conversation: conversation,
                    compact: _compact,
                    peerTyping: state?.peerTyping ?? false,
                    offline: state?.offline ?? false,
                    presence: presence,
                    now: now,
                    onBack: () =>
                        context.canPop() ? context.pop() : context.go('/app'),
                    onCall: canCall
                        ? () => _startCall(conversation, CallKind.audio)
                        : null,
                    onVideoCall: canCall
                        ? () => _startCall(conversation, CallKind.video)
                        : null,
                    onInfo: isGroup && conversation != null
                        ? () => GroupInfoSheet.show(context, conversation)
                        : null,
                    onProfile: conversation == null
                        ? null
                        : (isGroup
                              ? () => GroupInfoSheet.show(context, conversation)
                              : () => _openProfile(conversation)),
                  ),
                  OfflineBar(visible: state?.offline ?? false),
                  Expanded(
                    child: thread.when(
                      loading: () => const _ThreadSkeleton(),
                      error: (error, _) => _ThreadError(
                        message: error is AppFailure
                            ? error.userMessage
                            : 'Could not open this chat.',
                        onRetry: () => ref.invalidate(
                          chatThreadProvider(widget.conversationId),
                        ),
                      ),
                      data: (_) => InboxThread(
                        cells: cells,
                        peerTyping: state?.peerTyping ?? false,
                        controller: _scroll,
                        now: DateTime.now(),
                        onRetry: () => ref
                            .read(
                              chatThreadProvider(widget.conversationId)
                                  .notifier,
                            )
                            .retryFailed(),
                        onDelete: _confirmDelete,
                        myName: myName,
                        peerName: conversation?.displayName,
                        emptyState: InboxEmptyState(
                          peerName: conversation?.displayName ?? 'them',
                          onSuggestion: _onSuggestion,
                        ),
                      ),
                    ),
                  ),
                  const UploadProgressBar(),
                  ComposerBar(
                    controller: _input,
                    focusNode: _focus,
                    attachOpen: _attachOpen,
                    onSendText: _sendText,
                    onSendVoice: _sendVoice,
                    onPickPhoto: () => _pick(imagesOnly: true),
                    onPickFile: () => _pick(imagesOnly: false),
                    onTyping: () => ref
                        .read(
                          chatThreadProvider(widget.conversationId).notifier,
                        )
                        .notifyTyping(),
                    onToggleAttach: () {
                      _focus.unfocus();
                      setState(() => _attachOpen = !_attachOpen);
                    },
                  ),
                ],
              ),
              Positioned(
                left: 12,
                bottom: 96,
                child: AttachPopover(
                  open: _attachOpen,
                  onPhoto: () => _pick(imagesOnly: true),
                  onFile: () => _pick(imagesOnly: false),
                  onForceAudio: _openForceAudio,
                ),
              ),
              Positioned(
                right: 16,
                bottom: 104,
                child: JumpToLatest(
                  visible: !_atBottom || _unseen > 0,
                  count: _unseen,
                  onTap: () => _scrollToLatest(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreadSkeleton extends StatelessWidget {
  const _ThreadSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          color: InboxPalette.brand500,
        ),
      ),
    );
  }
}

class _ThreadError extends StatelessWidget {
  const _ThreadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 30,
              color: InboxPalette.muted,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: InboxPalette.muted,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
