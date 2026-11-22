import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';

import '../../../app/lifecycle.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../account_status/application/account_status_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../data/chat_local_store.dart';
import '../data/supabase_chat_repository.dart';
import '../data/supabase_message_change_source.dart';
import 'chat_journal_sync.dart';
import '../domain/chat_repository.dart';
import '../domain/conversation.dart';
import '../../force_audio/application/force_audio_providers.dart';
import '../../force_audio/domain/force_audio_alert.dart';
import '../../media/application/media_controller.dart';
import '../../media/domain/media_asset.dart';
import '../domain/message.dart';
import '../domain/message_merge.dart';

final _log = AppLogger('chat');

final chatLocalStoreProvider = Provider<ChatLocalStore?>(
  (ref) => ChatLocalStore.instance,
);

/// Optional until the server journal is deployed. A failure never advances the
/// journal cursor and is reported as offline rather than a complete sync.
final chatJournalSyncProvider = Provider.family<ChatJournalSync?, String>((
  ref,
  ownerId,
) {
  final store = ref.read(chatLocalStoreProvider);
  final session = ref.watch(authControllerProvider);
  if (!const bool.fromEnvironment('PULSE_JOURNAL_SYNC') ||
      store == null ||
      !AppConfig.isBackendConfigured ||
      session is! AuthSignedIn ||
      session.user.id != ownerId) {
    return null;
  }
  final source = SupabaseMessageChangeSource(
    Supabase.instance.client,
    ownerId,
    sessionIsCurrent: () =>
        ref.mounted && identical(ref.read(authControllerProvider), session),
  );
  return ChatJournalSyncImpl(
    source,
    store.journalStore,
    markRevision: source.markReadRevision,
  );
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  if (!AppConfig.isBackendConfigured) {
    throw const ConfigurationFailure('Supabase is not configured.');
  }
  return SupabaseChatRepository(Supabase.instance.client);
});

/// Conversation list. Refreshes on demand; the source of truth is Postgres.
class ConversationsController extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) return const [];
    return ref.read(chatRepositoryProvider).conversations();
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(chatRepositoryProvider).conversations(),
    );
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsController, List<Conversation>>(
      ConversationsController.new,
    );

/// One open conversation: cached messages first, then the server, then Realtime.
class ChatThreadState {
  const ChatThreadState({
    required this.messages,
    this.peerTyping = false,
    this.offline = false,
  });

  final List<Message> messages;
  final bool peerTyping;

  /// True when the last load came from the Hive cache (no network).
  final bool offline;

  ChatThreadState copyWith({
    List<Message>? messages,
    bool? peerTyping,
    bool? offline,
  }) => ChatThreadState(
    messages: messages ?? this.messages,
    peerTyping: peerTyping ?? this.peerTyping,
    offline: offline ?? this.offline,
  );
}

class ChatThreadController extends AsyncNotifier<ChatThreadState> {
  ChatThreadController(this.conversationId);

  /// Riverpod 3 families pass the argument to the constructor, not to build().
  final String conversationId;
  static const Duration typingThrottle = Duration(seconds: 3);
  static const Duration typingDisplay = Duration(seconds: 4);

  StreamSubscription<Message>? _live;
  StreamSubscription<bool>? _typing;
  Timer? _typingHide;
  DateTime? _lastTypingSent;
  final _uuid = const Uuid();

  ChatLocalStore? get _currentStore {
    final auth = ref.read(authControllerProvider);
    return auth is AuthSignedIn
        ? ref.read(chatLocalStoreProvider)?.forUser(auth.user.id)
        : null;
  }

  bool _isCurrentOwner(String id) {
    if (!ref.mounted) return false;
    final auth = ref.read(authControllerProvider);
    return auth is AuthSignedIn && auth.user.id == id;
  }

  void _reconcileOutbox(ChatLocalStore? store, Iterable<Message> messages) {
    if (store == null) return;
    unawaited(() async {
      try {
        await store.reconcileConfirmed(messages);
        await store.reconcileLegacyConfirmed(messages);
      } catch (_) {
        _log.warning('outbox_reconciliation_failed');
      }
    }());
  }

  @override
  Future<ChatThreadState> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) {
      return const ChatThreadState(messages: []);
    }

    final store = ref.read(chatLocalStoreProvider)?.forUser(auth.user.id);
    final cached = store?.cachedMessages(conversationId) ?? const <Message>[];
    final queued =
        store?.pendingFor(conversationId) ?? const <PendingMessage>[];
    final optimistic = queued.map(_pendingAsMessage).toList();

    var disposed = false;
    Timer? deferredRefresh;
    Timer? journalPoll;
    ref.onDispose(() {
      disposed = true;
      deferredRefresh?.cancel();
      journalPoll?.cancel();
      _live?.cancel();
      _typing?.cancel();
      _typingHide?.cancel();
    });

    final repo = ref.read(chatRepositoryProvider);
    final journal = ref.read(chatJournalSyncProvider(auth.user.id));
    final bufferedEvents = <Message>[];
    final refreshEvents = <Message>[];
    var loadingSnapshot = true;
    var refreshing = false;
    var refreshRequested = false;

    Future<void> refreshOnResume() async {
      if (disposed || !_isCurrentOwner(auth.user.id)) return;
      refreshRequested = true;
      if (refreshing || loadingSnapshot) return;
      refreshing = true;
      refreshRequested = false;
      refreshEvents.clear();
      try {
        final journalSnapshot = journal == null
            ? null
            : await journal.catchUp(auth.user.id, conversationId);
        final fresh =
            journalSnapshot?.messages ?? await repo.messages(conversationId);
        if (disposed ||
            !_isCurrentOwner(auth.user.id) ||
            !identical(ref.read(authControllerProvider), auth)) {
          return;
        }
        final current = state.value;
        if (current == null) return;
        // Journal snapshots are authoritative, including hard deletes. Realtime
        // events racing the snapshot request another journal pass instead of
        // being overlaid, which could resurrect an older deleted row.
        final merged = journal == null
            ? mergeConversationMessages(
                mergeConversationMessages(current.messages, fresh),
                refreshEvents,
              )
            : mergeConversationMessages(
                current.messages
                    .where((m) => m.delivery != DeliveryState.sent)
                    .toList(),
                fresh,
              );
        state = AsyncData(current.copyWith(messages: merged, offline: false));
        store?.cacheMessages(conversationId, merged);
        _reconcileOutbox(store, [...fresh, ...refreshEvents]);
        if (journal != null && !refreshRequested) {
          // Never acknowledge unseen messages before a complete journal pass.
          try {
            await journal.markRead(conversationId, journalSnapshot!.revision);
          } catch (_) {
            _log.warning('journal_mark_read_failed');
          }
        }
      } catch (_) {
        if (!disposed && _isCurrentOwner(auth.user.id)) {
          final current = state.value;
          if (current != null) {
            state = AsyncData(current.copyWith(offline: true));
          }
        }
      } finally {
        refreshing = false;
        refreshEvents.clear();
        if (refreshRequested && !disposed && _isCurrentOwner(auth.user.id)) {
          unawaited(refreshOnResume());
        }
      }
    }

    if (journal != null) {
      // Periodic catch-up covers a missed event even if no lifecycle transition
      // occurs. This is not a substitute for subscription-health monitoring.
      journalPoll = Timer.periodic(const Duration(seconds: 20), (_) {
        unawaited(refreshOnResume());
      });
    }
    ref.listen<AppLifecycleState>(appLifecycleProvider, (previous, next) {
      if (previous != AppLifecycleState.resumed &&
          next == AppLifecycleState.resumed) {
        unawaited(refreshOnResume());
      }
    });

    // Subscribe before the fetch. Events received while it is in flight must
    // not be discarded merely because AsyncNotifier has no value yet.
    _live = repo.newMessages(conversationId).listen((message) {
      if (!_isCurrentOwner(auth.user.id)) return;
      _reconcileOutbox(store, [message]);
      if (refreshing) refreshEvents.add(message);
      if (journal != null) unawaited(refreshOnResume());
      if (loadingSnapshot) {
        bufferedEvents.add(message);
        return;
      }
      final current = state.value;
      if (current == null) return;
      final previous = current.messages
          .where((m) => m.id == message.id)
          .firstOrNull;
      if (previous != null && mapEquals(previous.toMap(), message.toMap())) {
        return;
      }
      final merged = mergeConversationMessages(current.messages, [message]);
      state = AsyncData(current.copyWith(messages: merged));
      store?.cacheMessages(conversationId, merged);
      if (journal == null &&
          previous == null &&
          message.senderId != auth.user.id) {
        repo.markRead(conversationId);
      }
    });

    _typing = repo.typingSignals(conversationId).listen((_) {
      if (!_isCurrentOwner(auth.user.id)) return;
      final current = state.value ?? const ChatThreadState(messages: []);
      state = AsyncData(current.copyWith(peerTyping: true));
      _typingHide?.cancel();
      _typingHide = Timer(typingDisplay, () {
        if (!_isCurrentOwner(auth.user.id)) return;
        final latest = state.value;
        if (latest != null) {
          state = AsyncData(latest.copyWith(peerTyping: false));
        }
      });
    });

    List<Message> snapshot;
    var offline = false;
    try {
      snapshot = await repo.messages(conversationId);
      if (!_isCurrentOwner(auth.user.id)) {
        return const ChatThreadState(messages: []);
      }
      // Mark-read failure must not turn a successful message fetch into an
      // offline cache response that discards the server snapshot.
      if (journal == null) {
        try {
          await repo.markRead(conversationId);
        } catch (_) {
          _log.warning('initial_mark_read_failed');
        }
      }
    } on AppFailure catch (e) {
      _log.warning('thread_load_failed', data: {'code': e.code});
      snapshot = cached;
      offline = true;
    } catch (_) {
      snapshot = cached;
      offline = true;
    }
    if (!_isCurrentOwner(auth.user.id)) {
      return const ChatThreadState(messages: []);
    }
    final merged = mergeConversationMessages(
      mergeConversationMessages(optimistic, snapshot),
      bufferedEvents,
    );
    loadingSnapshot = false;
    store?.cacheMessages(conversationId, merged);
    if (!offline) _reconcileOutbox(store, [...snapshot, ...bufferedEvents]);
    // Let AsyncNotifier publish the initial value before the queued refresh.
    if ((refreshRequested || journal != null) && !disposed) {
      deferredRefresh = Timer(
        Duration.zero,
        () => unawaited(refreshOnResume()),
      );
    }
    return ChatThreadState(messages: merged, offline: offline);
  }

  Message _pendingAsMessage(PendingMessage p) => Message(
    id: 'pending:${p.clientId}',
    conversationId: p.conversationId,
    senderId: ref.read(authControllerProvider) is AuthSignedIn
        ? (ref.read(authControllerProvider) as AuthSignedIn).user.id
        : '',
    kind: MessageKind.text,
    body: p.body,
    createdAt: p.queuedAt,
    clientId: p.clientId,
    delivery: DeliveryState.pending,
  );

  /// Optimistic send: the bubble appears immediately as `pending`, then becomes
  /// `sent` or `failed`. A failed message goes into the Hive outbox so it can be
  /// retried (by the user or on the next successful connection).
  Future<void> send(String rawBody) async {
    final reason = Message.validateBody(rawBody);
    if (reason != null) throw ValidationFailure('body', reason);
    final body = rawBody.trim();
    final current = state.value ?? const ChatThreadState(messages: []);
    final clientId = _uuid.v4();
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthSignedIn) throw const AuthFailure('Please sign in again.');
    final myId = auth.user.id;

    final optimistic = Message(
      id: 'pending:$clientId',
      conversationId: conversationId,
      senderId: myId,
      kind: MessageKind.text,
      body: body,
      createdAt: DateTime.now(),
      clientId: clientId,
      delivery: DeliveryState.pending,
    );
    state = AsyncData(
      current.copyWith(messages: [...current.messages, optimistic]),
    );

    await _deliver(optimistic, clientId, body);
  }

  /// Uploads [media] with live progress, then sends a message referencing it.
  /// The upload itself is not queued offline — a half-uploaded file would be a
  /// lie — but a failure surfaces immediately and the user can retry.
  Future<void> sendMedia({
    required PickedMedia media,
    required MessageKind kind,

    /// Length of a voice note, so the receiver's bubble knows its duration.
    int? durationMs,
  }) async {
    // Bind the operation to the account that selected the file, before any
    // asynchronous upload. Never send an old user's upload as a new user.
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthSignedIn) throw const AuthFailure('Please sign in again.');
    final myId = auth.user.id;
    final mediaName = media.fileName;
    final upload = ref.read(mediaUploadProvider.notifier);
    final asset = await upload.upload(media);
    if (!_isCurrentOwner(myId)) {
      throw const AuthFailure(
        'Account changed during upload. Reopen the chat before retrying.',
      );
    }
    final current = state.value ?? const ChatThreadState(messages: []);
    final clientId = _uuid.v4();

    final optimistic = Message(
      id: 'pending:$clientId',
      conversationId: conversationId,
      senderId: myId,
      kind: kind,
      createdAt: DateTime.now(),
      mediaUrl: asset.secureUrl,
      mediaName: mediaName,
      mediaBytes: asset.bytes,
      durationMs: durationMs,
      clientId: clientId,
      delivery: DeliveryState.pending,
    );
    state = AsyncData(
      current.copyWith(messages: [...current.messages, optimistic]),
    );

    try {
      final saved = await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            conversationId: conversationId,
            clientId: clientId,
            body: '',
            kind: kind,
            mediaUrl: asset.secureUrl,
            mediaName: mediaName,
            mediaBytes: asset.bytes,
            durationMs: durationMs,
          );
      if (!_isCurrentOwner(myId)) {
        throw const AuthFailure(
          'Account changed. Check the original chat before retrying.',
        );
      }
      _replace(optimistic.id, saved);
      ref.read(conversationsProvider.notifier).refresh();
    } on AppFailure {
      // The bytes may already be on Cloudinary. Never write an old account's
      // failure into the newly signed-in account's thread.
      if (_isCurrentOwner(myId)) {
        _replace(
          optimistic.id,
          optimistic.copyWith(delivery: DeliveryState.failed),
        );
      }
      rethrow;
    } finally {
      if (_isCurrentOwner(myId)) upload.clear();
    }
  }

  /// Sends a Force Audio: the message row plus the alert row that lets the
  /// receiver verify it. Returns the alert, or null when only the message landed
  /// (the caller reports that honestly instead of claiming success).
  Future<ForceAudioAlert?> sendForceAudio({
    required String mediaUrl,
    required int sizeBytes,
    required int durationMs,
  }) async {
    final current = state.value ?? const ChatThreadState(messages: []);
    final clientId = _uuid.v4();
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthSignedIn) throw const AuthFailure('Please sign in again.');
    final myId = auth.user.id;

    final recipientId = _recipientId();
    if (recipientId == null) {
      throw const ValidationFailure(
        'force_audio',
        'Could not work out who to send this to. Reopen the chat and retry.',
      );
    }

    final optimistic = Message(
      id: 'pending:$clientId',
      conversationId: conversationId,
      senderId: myId,
      kind: MessageKind.forceAudio,
      createdAt: DateTime.now(),
      mediaUrl: mediaUrl,
      mediaBytes: sizeBytes,
      clientId: clientId,
      delivery: DeliveryState.pending,
    );
    state = AsyncData(
      current.copyWith(messages: [...current.messages, optimistic]),
    );

    var messageSaved = false;
    try {
      final saved = await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            conversationId: conversationId,
            clientId: clientId,
            body: '',
            kind: MessageKind.forceAudio,
            mediaUrl: mediaUrl,
            mediaBytes: sizeBytes,
            durationMs: durationMs,
          );
      if (!_isCurrentOwner(myId)) {
        throw const AuthFailure(
          'Account changed. Check the original chat before retrying.',
        );
      }
      _replace(optimistic.id, saved);
      messageSaved = true;

      final alert = await ref
          .read(forceAudioRepositoryProvider)
          .createAlert(
            requestId: clientId,
            conversationId: conversationId,
            recipientId: recipientId,
            mediaUrl: mediaUrl,
            durationMs: durationMs,
            sizeBytes: sizeBytes,
            messageId: saved.id,
          );
      if (!_isCurrentOwner(myId)) {
        throw const AuthFailure(
          'Account changed. Check the original chat before retrying.',
        );
      }
      return alert;
    } on AppFailure {
      if (!_isCurrentOwner(myId)) rethrow;
      if (messageSaved) {
        // The message is already confirmed; don't resurrect a failed copy.
        // The composer can honestly report that the alert was not created.
        return null;
      }
      _replace(
        optimistic.id,
        optimistic.copyWith(delivery: DeliveryState.failed),
      );
      rethrow;
    }
  }

  /// The other member of this direct conversation, from the conversation list.
  String? _recipientId() {
    final conversations = ref.read(conversationsProvider).value;
    if (conversations == null) return null;
    for (final c in conversations) {
      if (c.id == conversationId) return c.peer.id;
    }
    return null;
  }

  Future<void> _deliver(
    Message optimistic,
    String clientId,
    String body, {
    bool fromRetry = false,
  }) async {
    final owner = optimistic.senderId;
    final store = ref.read(chatLocalStoreProvider)?.forUser(owner);
    // Persist the idempotency key before the network request. If Hive is not
    // available, allow online send but return failures to the composer.
    if (store != null) {
      try {
        await store.enqueue(
          PendingMessage(
            clientId: clientId,
            conversationId: conversationId,
            body: body,
            queuedAt: optimistic.createdAt,
          ),
        );
      } catch (_) {
        if (_isCurrentOwner(owner)) {
          if (fromRetry) {
            _replace(
              optimistic.id,
              optimistic.copyWith(delivery: DeliveryState.failed),
            );
          } else {
            _remove(optimistic.id);
          }
        }
        throw const StorageFailure(insufficientSpace: false);
      }
    }
    // The original account may have changed while persistence was pending.
    if (!_isCurrentOwner(owner)) return;

    Future<void> discardPending() async {
      try {
        await store?.dequeue(clientId);
      } catch (_) {
        _log.warning('outbox_dequeue_failed');
      }
    }

    try {
      final saved = await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            conversationId: conversationId,
            clientId: clientId,
            body: body,
          );
      await discardPending();
      if (!_isCurrentOwner(owner)) return;
      _replace(optimistic.id, saved);
      ref.read(conversationsProvider.notifier).refresh();
    } on AccountSuspendedFailure {
      await discardPending();
      if (!_isCurrentOwner(owner)) return;
      _log.warning('send_refused_account_on_hold');
      _remove(optimistic.id);
      unawaited(ref.read(accountStatusControllerProvider.notifier).check());
    } on AdminControlFailure {
      if (!_isCurrentOwner(owner)) return;
      if (fromRetry) {
        _replace(
          optimistic.id,
          optimistic.copyWith(delivery: DeliveryState.failed),
        );
      } else {
        await discardPending();
        if (_isCurrentOwner(owner)) _remove(optimistic.id);
      }
      rethrow;
    } on AppFailure catch (e) {
      _log.warning('send_failed', data: {'code': e.code});
      if (!_isCurrentOwner(owner)) return;
      if (!e.isRetryable) {
        if (fromRetry) {
          _replace(
            optimistic.id,
            optimistic.copyWith(delivery: DeliveryState.failed),
          );
        } else {
          await discardPending();
          if (_isCurrentOwner(owner)) _remove(optimistic.id);
        }
        rethrow;
      }
      if (store == null) {
        _remove(optimistic.id);
        rethrow;
      }
      _replace(
        optimistic.id,
        optimistic.copyWith(delivery: DeliveryState.failed),
      );
    } catch (_) {
      if (!_isCurrentOwner(owner)) return;
      if (store == null) {
        _remove(optimistic.id);
        throw const NetworkFailure();
      }
      _replace(
        optimistic.id,
        optimistic.copyWith(delivery: DeliveryState.failed),
      );
    }
  }

  /// Takes a bubble away entirely — used when the server says the account may
  /// not write at all, where "failed, retry?" would be the wrong offer.
  void _remove(String id) {
    final current = state.value;
    if (current == null) return;
    final list = current.messages.where((m) => m.id != id).toList();
    state = AsyncData(current.copyWith(messages: list));
    _currentStore?.cacheMessages(conversationId, list);
  }

  void _replace(String oldId, Message next) {
    final current = state.value;
    if (current == null) return;
    final remaining = current.messages.where((m) => m.id != oldId);
    final sorted = mergeConversationMessages(remaining, [next]);
    state = AsyncData(current.copyWith(messages: sorted));
    _currentStore?.cacheMessages(conversationId, sorted);
  }

  /// Retries every failed message in this conversation, in order.
  Future<void> retryFailed() async {
    final current = state.value;
    final store = _currentStore;
    if (current == null) return;
    final failed = current.messages
        .where((m) => m.delivery != DeliveryState.sent)
        .toList();
    for (final message in failed) {
      final clientId = message.clientId;
      if (clientId == null || message.body == null) continue;
      _replace(message.id, message.copyWith(delivery: DeliveryState.pending));
      await _deliver(
        message.copyWith(delivery: DeliveryState.pending),
        clientId,
        message.body!,
        fromRetry: true,
      );
    }
    store?.pending();
  }

  /// Called on every keystroke; throttled to one broadcast per 3 seconds.
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < typingThrottle) {
      return;
    }
    _lastTypingSent = now;
    ref.read(chatRepositoryProvider).broadcastTyping(conversationId);
  }

  Future<void> deleteMessage(Message message) async {
    try {
      await ref.read(chatRepositoryProvider).deleteMessage(message.id);
      _replace(message.id, message.copyWith(isDeleted: true));
    } on AppFailure catch (e) {
      _log.warning('delete_failed', data: {'code': e.code});
      rethrow;
    }
  }
}

final chatThreadProvider =
    AsyncNotifierProvider.family<ChatThreadController, ChatThreadState, String>(
      ChatThreadController.new,
    );

/// Everyone I can start a chat with.
final peopleProvider = FutureProvider<List<ChatPeerSummary>>((ref) async {
  return ref.watch(chatRepositoryProvider).people();
});

/// Starts (or reuses) a direct conversation with another account.
final startConversationProvider = FutureProvider.family<String, String>((
  ref,
  otherUserId,
) async {
  final id = await ref
      .read(chatRepositoryProvider)
      .startDirectConversation(otherUserId);
  ref.invalidate(conversationsProvider);
  return id;
});

/// Members + roles of a group (RLS returns rows only to members).
final groupMembersProvider = FutureProvider.family<List<GroupMember>, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatRepositoryProvider).groupMembers(conversationId);
});
