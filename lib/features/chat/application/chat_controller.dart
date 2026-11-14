import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../auth/application/auth_controller.dart';
import '../data/chat_local_store.dart';
import '../data/supabase_chat_repository.dart';
import '../domain/chat_repository.dart';
import '../domain/conversation.dart';
import '../domain/message.dart';

final _log = AppLogger('chat');

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

  @override
  Future<ChatThreadState> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthSignedIn) {
      return const ChatThreadState(messages: []);
    }

    final store = ChatLocalStore.instance;
    final cached = store?.cachedMessages(conversationId) ?? const <Message>[];
    final queued =
        store?.pendingFor(conversationId) ?? const <PendingMessage>[];
    final optimistic = queued.map(_pendingAsMessage).toList();

    ref.onDispose(() {
      _live?.cancel();
      _typing?.cancel();
      _typingHide?.cancel();
    });

    final repo = ref.read(chatRepositoryProvider);

    // Realtime: every insert in this conversation, including my own from another
    // device. Deduplicated by id downstream.
    _live = repo.newMessages(conversationId).listen((message) {
      final current = state.value;
      if (current == null) return;
      if (current.messages.any((m) => m.id == message.id)) return;
      final merged = [...current.messages, message]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state = AsyncData(current.copyWith(messages: merged));
      store?.cacheMessages(conversationId, merged);
      if (message.senderId != auth.user.id) {
        repo.markRead(conversationId);
      }
    });

    _typing = repo.typingSignals(conversationId).listen((_) {
      final current = state.value ?? const ChatThreadState(messages: []);
      state = AsyncData(current.copyWith(peerTyping: true));
      _typingHide?.cancel();
      _typingHide = Timer(typingDisplay, () {
        final latest = state.value;
        if (latest != null) {
          state = AsyncData(latest.copyWith(peerTyping: false));
        }
      });
    });

    try {
      final fresh = await repo.messages(conversationId);
      store?.cacheMessages(conversationId, fresh);
      final merged = _mergeById(fresh, optimistic);
      await repo.markRead(conversationId);
      return ChatThreadState(messages: merged);
    } on AppFailure catch (e) {
      // Offline: show the cache and say so, instead of an error screen.
      _log.warning('thread_load_failed', data: {'code': e.code});
      return ChatThreadState(
        messages: _mergeById(cached, optimistic),
        offline: true,
      );
    } catch (_) {
      return ChatThreadState(
        messages: _mergeById(cached, optimistic),
        offline: true,
      );
    }
  }

  List<Message> _mergeById(List<Message> base, List<Message> extra) {
    final byId = {for (final m in base) m.id: m};
    for (final m in extra) {
      byId.putIfAbsent(m.id, () => m);
    }
    final list = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
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
    final myId = auth is AuthSignedIn ? auth.user.id : '';

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

  Future<void> _deliver(
    Message optimistic,
    String clientId,
    String body,
  ) async {
    final store = ChatLocalStore.instance;
    try {
      final saved = await ref
          .read(chatRepositoryProvider)
          .sendMessage(
            conversationId: conversationId,
            clientId: clientId,
            body: body,
          );
      store?.dequeue(clientId);
      _replace(optimistic.id, saved);
      ref.read(conversationsProvider.notifier).refresh();
    } on AppFailure catch (e) {
      _log.warning('send_failed', data: {'code': e.code});
      store?.enqueue(
        PendingMessage(
          clientId: clientId,
          conversationId: conversationId,
          body: body,
          queuedAt: optimistic.createdAt,
        ),
      );
      _replace(
        optimistic.id,
        optimistic.copyWith(delivery: DeliveryState.failed),
      );
    } catch (_) {
      store?.enqueue(
        PendingMessage(
          clientId: clientId,
          conversationId: conversationId,
          body: body,
          queuedAt: optimistic.createdAt,
        ),
      );
      _replace(
        optimistic.id,
        optimistic.copyWith(delivery: DeliveryState.failed),
      );
    }
  }

  void _replace(String oldId, Message next) {
    final current = state.value;
    if (current == null) return;
    final list = current.messages
        .map((m) => m.id == oldId ? next : m)
        .where((m) => m.id != next.id || identical(m, next))
        .toList();
    // Drop the optimistic row once its server twin is present.
    final deduped = <String, Message>{}
      ..addEntries(list.map((m) => MapEntry(m.clientId ?? m.id, m)));
    final sorted = deduped.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    state = AsyncData(current.copyWith(messages: sorted));
    ChatLocalStore.instance?.cacheMessages(conversationId, sorted);
  }

  /// Retries every failed message in this conversation, in order.
  Future<void> retryFailed() async {
    final current = state.value;
    final store = ChatLocalStore.instance;
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
