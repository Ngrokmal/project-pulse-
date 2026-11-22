import 'dart:async';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/app/lifecycle.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/auth/application/auth_controller.dart';
import 'package:pulse/features/auth/domain/auth_repository.dart';
import 'package:pulse/features/chat/application/chat_controller.dart';
import 'package:pulse/features/chat/application/chat_journal_sync.dart';
import 'package:pulse/features/chat/data/chat_local_store.dart';
import 'package:pulse/features/chat/data/hive_message_sync_store.dart';
import 'package:pulse/features/chat/domain/chat_repository.dart';
import 'package:pulse/features/chat/domain/conversation.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/media/application/media_controller.dart';
import 'package:pulse/features/media/domain/media_asset.dart';
import 'package:pulse/features/force_audio/application/force_audio_providers.dart';
import 'package:pulse/features/force_audio/domain/force_audio_repository.dart';
import 'package:pulse/features/force_audio/domain/force_audio_alert.dart';

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(PulseUser(id: 'me', email: null));
  void switchTo(String id) =>
      state = AuthSignedIn(PulseUser(id: id, email: null));
}

class _ForceAudio implements ForceAudioRepository {
  int created = 0;
  bool failWithNetwork = false;
  @override
  Future<ForceAudioAlert> createAlert({
    required String requestId,
    required String conversationId,
    required String recipientId,
    required String mediaUrl,
    required int durationMs,
    required int sizeBytes,
    String? messageId,
    String mimeType = 'audio/mp4',
  }) async {
    created++;
    if (failWithNetwork) throw const NetworkFailure();
    throw StateError('unexpected alert');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedUpload extends MediaUploadController {
  static late Completer<CloudinaryAsset> gate;
  @override
  Future<CloudinaryAsset> upload(PickedMedia media) => gate.future;
}

const _pickedMedia = PickedMedia(
  path: '/synthetic',
  fileName: 'photo.png',
  sizeBytes: 1,
  resourceType: MediaResourceType.image,
);
const _uploadedMedia = CloudinaryAsset(
  secureUrl: 'https://example.invalid/photo.png',
  publicId: 'test',
  resourceType: MediaResourceType.image,
  bytes: 1,
);

class _Journal implements ChatJournalSync {
  int calls = 0;
  final pending = <Completer<List<Message>>>[];
  @override
  Future<JournalSnapshot> catchUp(String ownerId, String conversationId) {
    calls++;
    final gate = Completer<List<Message>>();
    pending.add(gate);
    return gate.future.then(
      (messages) => JournalSnapshot(messages.length, messages),
    );
  }

  final marked = <int>[];
  @override
  Future<void> markRead(String conversationId, int revision) async {
    marked.add(revision);
  }
}

class _Chat implements ChatRepository {
  final snapshot = Completer<List<Message>>();
  Completer<List<Message>>? resumeSnapshot;
  int fetches = 0;
  final read = Completer<void>();
  int readCalls = 0;
  final events = StreamController<Message>.broadcast(sync: true);
  AppFailure? sendFailure;
  List<Conversation> conversationRows = [];
  void Function(String clientId)? beforeSend;
  Completer<Message>? sendGate;
  @override
  Future<Message> sendMessage({
    required String conversationId,
    required String clientId,
    required String body,
    MessageKind kind = MessageKind.text,
    String? mediaUrl,
    String? mediaName,
    int? mediaBytes,
    int? durationMs,
  }) async {
    beforeSend?.call(clientId);
    if (sendFailure case final failure?) throw failure;
    if (sendGate case final gate?) return gate.future;
    return _message('saved', clientId: clientId);
  }

  @override
  Future<List<Conversation>> conversations() async => conversationRows;

  @override
  Future<List<Message>> messages(String conversationId, {int limit = 100}) {
    fetches++;
    return fetches > 1 && resumeSnapshot != null
        ? resumeSnapshot!.future
        : snapshot.future;
  }

  @override
  Future<void> markRead(String conversationId) {
    readCalls++;
    return read.future;
  }

  @override
  Stream<Message> newMessages(String conversationId) => events.stream;
  @override
  Stream<bool> typingSignals(String conversationId) => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _message(String id, {String? clientId, bool deleted = false}) =>
    Message(
      id: id,
      clientId: clientId,
      conversationId: 'conv',
      senderId: 'other',
      kind: MessageKind.text,
      body: id,
      isDeleted: deleted,
      createdAt: DateTime.utc(2026),
    );

void main() {
  test('journal refresh removes hard-deleted rows and repeats for racing realtime event', () async {
    final repo = _Chat();
    final journal = _Journal();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        chatRepositoryProvider.overrideWithValue(repo),
        chatJournalSyncProvider.overrideWith((ref, owner) => journal),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repo.events.close();
    });
    final provider = chatThreadProvider('conv');
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final ready = container.read(provider.future);
    repo.snapshot.complete([_message('old')]);
    repo.read.complete();
    await ready;
    await Future<void>.delayed(Duration.zero);
    await container.pump();
    expect(journal.calls, 1);
    expect(repo.readCalls, 0);
    repo.events.add(_message('race'));
    journal.pending[0].complete([_message('kept')]);
    await container.pump();
    expect(journal.calls, 2);
    expect(repo.readCalls, 0);
    journal.pending[1].complete([_message('kept'), _message('race')]);
    await container.pump();
    expect(container.read(provider).value!.messages.map((m) => m.id), [
      'kept',
      'race',
    ]);
    expect(repo.readCalls, 0);
    expect(journal.marked, [2]);
  });
  test(
    'failed journal catch-up never marks the incomplete snapshot as read',
    () async {
      final repo = _Chat();
      final journal = _Journal();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatJournalSyncProvider.overrideWith((ref, owner) => journal),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final ready = container.read(provider.future);
      repo.snapshot.complete([_message('latest')]);
      repo.read.complete();
      await ready;
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      expect(journal.calls, 1);
      expect(repo.readCalls, 0);
      journal.pending.single.completeError(StateError('offline'));
      await container.pump();
      expect(repo.readCalls, 0);
      expect(container.read(provider).value!.offline, isTrue);
      expect(container.read(provider).value!.messages.single.id, 'latest');
    },
  );
  test(
    'events during snapshot and mark-read are kept and deduplicated',
    () async {
      final repo = _Chat();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final result = container.read(provider.future);
      await container.pump();
      repo.events.add(_message('one', clientId: 'same'));
      repo.snapshot.complete([_message('one', clientId: 'same')]);
      await container.pump();
      repo.events.add(_message('two'));
      repo.read.complete();
      final state = await result;
      expect(state.offline, isFalse);
      expect(state.messages.map((m) => m.id), ['one', 'two']);
      repo.events.add(_message('one', clientId: 'same', deleted: true));
      await container.pump();
      expect(container.read(provider).value!.messages.first.isDeleted, isTrue);
    },
  );
  test(
    'resume refresh recovers a missed message and keeps a newer live update',
    () async {
      final repo = _Chat()..resumeSnapshot = Completer<List<Message>>();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(null),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([_message('one')]);
      repo.read.complete();
      await ready;
      final lifecycle = container.read(appLifecycleProvider.notifier);
      lifecycle.set(AppLifecycleState.paused);
      lifecycle.set(AppLifecycleState.resumed);
      await container.pump();
      expect(repo.fetches, 2);
      repo.events.add(_message('one', deleted: true));
      repo.resumeSnapshot!.complete([_message('one'), _message('missed')]);
      await container.pump();
      final rows = container.read(provider).value!.messages;
      expect(rows.map((m) => m.id), ['missed', 'one']);
      expect(rows.singleWhere((m) => m.id == 'one').isDeleted, isTrue);
    },
  );
  test(
    'resume while initial snapshot loads schedules a follow-up refresh',
    () async {
      final repo = _Chat()..resumeSnapshot = Completer<List<Message>>();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(null),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final ready = container.read(provider.future);
      await container.pump();
      final lifecycle = container.read(appLifecycleProvider.notifier);
      lifecycle.set(AppLifecycleState.paused);
      lifecycle.set(AppLifecycleState.resumed);
      repo.snapshot.complete([_message('one')]);
      repo.read.complete();
      await ready;
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      expect(repo.fetches, 2);
      repo.resumeSnapshot!.complete([_message('two')]);
      await container.pump();
      expect(
        container.read(provider).value!.messages.map((m) => m.id),
        contains('two'),
      );
    },
  );
  test('a second resume during a refresh schedules another fetch', () async {
    final repo = _Chat()..resumeSnapshot = Completer<List<Message>>();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        chatRepositoryProvider.overrideWithValue(repo),
        chatLocalStoreProvider.overrideWithValue(null),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repo.events.close();
    });
    final provider = chatThreadProvider('conv');
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final ready = container.read(provider.future);
    await container.pump();
    repo.snapshot.complete([_message('one')]);
    repo.read.complete();
    await ready;
    final lifecycle = container.read(appLifecycleProvider.notifier);
    lifecycle.set(AppLifecycleState.paused);
    lifecycle.set(AppLifecycleState.resumed);
    await container.pump();
    final first = repo.resumeSnapshot!;
    lifecycle.set(AppLifecycleState.paused);
    lifecycle.set(AppLifecycleState.resumed);
    final second = Completer<List<Message>>();
    repo.resumeSnapshot = second;
    first.complete([_message('two')]);
    await container.pump();
    expect(repo.fetches, 3);
    second.complete([_message('three')]);
    await container.pump();
    expect(
      container.read(provider).value!.messages.map((m) => m.id),
      contains('three'),
    );
  });
  test('an old account refresh cannot overwrite a switched account', () async {
    final repo = _Chat()..resumeSnapshot = Completer<List<Message>>();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        chatRepositoryProvider.overrideWithValue(repo),
        chatLocalStoreProvider.overrideWithValue(null),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repo.events.close();
    });
    final provider = chatThreadProvider('conv');
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final ready = container.read(provider.future);
    await container.pump();
    repo.snapshot.complete([_message('initial')]);
    repo.read.complete();
    await ready;
    final lifecycle = container.read(appLifecycleProvider.notifier);
    lifecycle.set(AppLifecycleState.paused);
    lifecycle.set(AppLifecycleState.resumed);
    await container.pump();
    final oldRefresh = repo.resumeSnapshot!;
    final newSnapshot = Completer<List<Message>>();
    repo.resumeSnapshot = newSnapshot;
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(
      'other-account',
    );
    await container.pump();
    newSnapshot.complete([_message('new-account')]);
    await container.pump();
    oldRefresh.complete([_message('old-account-secret')]);
    await container.pump();
    expect(container.read(provider).value!.messages.map((m) => m.id), [
      'new-account',
    ]);
  });
  test(
    'failed resume retains messages and a later resume can recover',
    () async {
      final repo = _Chat()..resumeSnapshot = Completer<List<Message>>();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(null),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([_message('one')]);
      repo.read.complete();
      await ready;
      final lifecycle = container.read(appLifecycleProvider.notifier);
      lifecycle.set(AppLifecycleState.paused);
      lifecycle.set(AppLifecycleState.resumed);
      await container.pump();
      repo.resumeSnapshot!.completeError(StateError('offline'));
      await container.pump();
      expect(container.read(provider).value!.offline, isTrue);
      expect(container.read(provider).value!.messages.single.id, 'one');
      repo.resumeSnapshot = Completer<List<Message>>();
      lifecycle.set(AppLifecycleState.paused);
      lifecycle.set(AppLifecycleState.resumed);
      await container.pump();
      repo.resumeSnapshot!.complete([_message('one'), _message('two')]);
      await container.pump();
      expect(container.read(provider).value!.offline, isFalse);
      expect(container.read(provider).value!.messages.map((m) => m.id), [
        'one',
        'two',
      ]);
    },
  );
  test(
    'permanent send denial is surfaced and not left as a retryable bubble',
    () async {
      final repo = _Chat()
        ..sendFailure = const ServerFailure(
          statusCode: 403,
          safeCode: 'blocked',
        );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final result = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([]);
      repo.read.complete();
      await result;
      await expectLater(
        container.read(provider.notifier).send('hello'),
        throwsA(isA<ServerFailure>()),
      );
      expect(container.read(provider).value!.messages, isEmpty);
    },
  );
  test('offline without local store returns the draft instead of pretending to queue it', () async {
    final repo = _Chat()..sendFailure = const NetworkFailure();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        chatRepositoryProvider.overrideWithValue(repo),
        chatLocalStoreProvider.overrideWithValue(null),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repo.events.close();
    });
    final provider = chatThreadProvider('conv');
    final result = container.read(provider.future);
    await container.pump();
    repo.snapshot.complete([]);
    repo.read.complete();
    await result;
    await expectLater(
      container.read(provider.notifier).send('unsent draft'),
      throwsA(isA<NetworkFailure>()),
    );
    expect(container.read(provider).value!.messages, isEmpty);
  });
  test(
    'a matching server snapshot reconciles an outbox item after restart',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'pulse-reconcile-test-',
      );
      Hive.init(dir.path);
      final cache = await Hive.openBox<String>('cache');
      final outbox = await Hive.openBox<String>('outbox');
      final root = ChatLocalStore.forTesting(cache, outbox);
      await root
          .forUser('me')
          .enqueue(
            PendingMessage(
              clientId: 'client-1',
              conversationId: 'conv',
              body: 'delivered',
              queuedAt: DateTime.utc(2026),
            ),
          );
      final repo = _Chat();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(root),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
        await Hive.close();
        await dir.delete(recursive: true);
      });
      final provider = chatThreadProvider('conv');
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([
        Message(
          id: 'server-row',
          clientId: 'client-1',
          conversationId: 'conv',
          senderId: 'me',
          kind: MessageKind.text,
          body: 'delivered',
          createdAt: DateTime.utc(2026),
        ),
      ]);
      repo.read.complete();
      final state = await ready;
      await container.pump();
      await outbox.flush();
      expect(state.messages.single.id, 'server-row');
      expect(root.forUser('me').pending(), isEmpty);
    },
  );
  test('a refused retry retains the older failed draft', () async {
    final dir = await Directory.systemTemp.createTemp('pulse-outbox-test-');
    Hive.init(dir.path);
    final cache = await Hive.openBox<String>('cache');
    final outbox = await Hive.openBox<String>('outbox');
    final root = ChatLocalStore.forTesting(cache, outbox);
    final repo = _Chat()..sendFailure = const NetworkFailure();
    repo.beforeSend = (id) =>
        expect(root.forUser('me').pending().single.clientId, id);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        chatRepositoryProvider.overrideWithValue(repo),
        chatLocalStoreProvider.overrideWithValue(root),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repo.events.close();
      await Hive.close();
      await dir.delete(recursive: true);
    });
    final provider = chatThreadProvider('conv');
    final result = container.read(provider.future);
    await container.pump();
    repo.snapshot.complete([]);
    repo.read.complete();
    await result;
    await container.read(provider.notifier).send('unsent draft');
    expect(
      container.read(provider).value!.messages.single.delivery,
      DeliveryState.failed,
    );
    repo.sendFailure = const AdminControlFailure('message_send_disabled');
    await expectLater(
      container.read(provider.notifier).retryFailed(),
      throwsA(isA<AdminControlFailure>()),
    );
    final failed = container.read(provider).value!.messages.single;
    expect(failed.delivery, DeliveryState.failed);
    expect(failed.body, 'unsent draft');
    expect(root.forUser('me').pending().single.body, 'unsent draft');
  });
  test(
    'retry reuses the same client id and removes a confirmed outbox item',
    () async {
      final dir = await Directory.systemTemp.createTemp('pulse-retry-test-');
      Hive.init(dir.path);
      final cache = await Hive.openBox<String>('cache');
      final outbox = await Hive.openBox<String>('outbox');
      final root = ChatLocalStore.forTesting(cache, outbox);
      final ids = <String>[];
      final repo = _Chat()..sendFailure = const NetworkFailure();
      repo.beforeSend = ids.add;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(root),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
        await Hive.close();
        await dir.delete(recursive: true);
      });
      final provider = chatThreadProvider('conv');
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([]);
      repo.read.complete();
      await ready;
      await container.read(provider.notifier).send('draft');
      expect(root.forUser('me').pending(), hasLength(1));
      repo.sendFailure = null;
      await container.read(provider.notifier).retryFailed();
      expect(ids, hasLength(2));
      expect(ids.first, ids.last);
      expect(root.forUser('me').pending(), isEmpty);
      expect(
        container.read(provider).value!.messages.single.delivery,
        DeliveryState.sent,
      );
    },
  );
  test('storage write failure does not start a network send', () async {
    final dir = await Directory.systemTemp.createTemp('pulse-failed-store-');
    Hive.init(dir.path);
    final cache = await Hive.openBox<String>('cache');
    final outbox = await Hive.openBox<String>('outbox');
    final root = ChatLocalStore.forTesting(cache, outbox);
    var sent = false;
    final repo = _Chat()..beforeSend = (_) => sent = true;
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        chatRepositoryProvider.overrideWithValue(repo),
        chatLocalStoreProvider.overrideWithValue(root),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repo.events.close();
      await Hive.close();
      await dir.delete(recursive: true);
    });
    final provider = chatThreadProvider('conv');
    final ready = container.read(provider.future);
    await container.pump();
    repo.snapshot.complete([]);
    repo.read.complete();
    await ready;
    await outbox.close();
    await expectLater(
      container.read(provider.notifier).send('draft'),
      throwsA(isA<StorageFailure>()),
    );
    expect(sent, isFalse);
    expect(container.read(provider).value!.messages, isEmpty);
  });
  test(
    'an in-flight send from the old account cannot update the new account',
    () async {
      final dir = await Directory.systemTemp.createTemp('pulse-switch-test-');
      Hive.init(dir.path);
      final cache = await Hive.openBox<String>('cache');
      final outbox = await Hive.openBox<String>('outbox');
      final root = ChatLocalStore.forTesting(cache, outbox);
      final entered = Completer<String>();
      final repo = _Chat()..sendGate = Completer<Message>();
      repo.beforeSend = (id) => entered.complete(id);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(root),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
        await Hive.close();
        await dir.delete(recursive: true);
      });
      final provider = chatThreadProvider('conv');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([]);
      repo.read.complete();
      await ready;
      final send = container.read(provider.notifier).send('old account draft');
      final clientId = await entered.future;
      expect(root.forUser('me').pending().single.body, 'old account draft');
      (container.read(authControllerProvider.notifier) as _Auth).switchTo(
        'other',
      );
      await container.pump();
      await container.read(provider.future);
      repo.sendGate!.complete(_message('saved-old', clientId: clientId));
      await send;
      await container.pump();
      expect(container.read(provider).value!.messages, isEmpty);
      expect(root.forUser('other').pending(), isEmpty);
      expect(root.forUser('other').cachedMessages('conv'), isEmpty);
      expect(root.forUser('me').pending(), isEmpty);
    },
  );
  test(
    'account switch during media upload prevents send under new account',
    () async {
      _DelayedUpload.gate = Completer<CloudinaryAsset>();
      final repo = _Chat();
      var sent = false;
      repo.beforeSend = (_) => sent = true;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(null),
          mediaUploadProvider.overrideWith(_DelayedUpload.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([]);
      repo.read.complete();
      await ready;
      final send = container
          .read(provider.notifier)
          .sendMedia(media: _pickedMedia, kind: MessageKind.image);
      final handled = expectLater(send, throwsA(isA<AuthFailure>()));
      (container.read(authControllerProvider.notifier) as _Auth).switchTo(
        'other',
      );
      await container.pump();
      await container.read(provider.future);
      _DelayedUpload.gate.complete(_uploadedMedia);
      await handled;
      await container.pump();
      expect(sent, isFalse);
      expect(container.read(provider).value!.messages, isEmpty);
    },
  );
  test('account switch during media send cannot update the new chat', () async {
    _DelayedUpload.gate = Completer<CloudinaryAsset>();
    final repo = _Chat()..sendGate = Completer<Message>();
    final entered = Completer<void>();
    repo.beforeSend = (_) => entered.complete();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        chatRepositoryProvider.overrideWithValue(repo),
        chatLocalStoreProvider.overrideWithValue(null),
        mediaUploadProvider.overrideWith(_DelayedUpload.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await repo.events.close();
    });
    final provider = chatThreadProvider('conv');
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final ready = container.read(provider.future);
    await container.pump();
    repo.snapshot.complete([]);
    repo.read.complete();
    await ready;
    final send = container
        .read(provider.notifier)
        .sendMedia(media: _pickedMedia, kind: MessageKind.image);
    final handled = expectLater(send, throwsA(isA<AuthFailure>()));
    _DelayedUpload.gate.complete(_uploadedMedia);
    await entered.future;
    (container.read(authControllerProvider.notifier) as _Auth).switchTo(
      'other',
    );
    await container.pump();
    await container.read(provider.future);
    repo.sendGate!.complete(_message('old-saved'));
    await handled;
    await container.pump();
    expect(container.read(provider).value!.messages, isEmpty);
  });
  test(
    'realtime messages arriving during media upload remain visible',
    () async {
      _DelayedUpload.gate = Completer<CloudinaryAsset>();
      final repo = _Chat();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(null),
          mediaUploadProvider.overrideWith(_DelayedUpload.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([]);
      repo.read.complete();
      await ready;
      final send = container
          .read(provider.notifier)
          .sendMedia(media: _pickedMedia, kind: MessageKind.image);
      repo.events.add(_message('incoming'));
      await container.pump();
      _DelayedUpload.gate.complete(_uploadedMedia);
      await send;
      await container.pump();
      expect(
        container.read(provider).value!.messages.map((m) => m.id),
        contains('incoming'),
      );
    },
  );
  test(
    'account switch during force audio send cannot alert as the new account',
    () async {
      final repo = _Chat()
        ..sendGate = Completer<Message>()
        ..conversationRows = [
          const Conversation(
            id: 'conv',
            peer: ChatPeer(id: 'peer', displayName: 'Peer'),
          ),
        ];
      final alerts = _ForceAudio();
      final entered = Completer<void>();
      repo.beforeSend = (_) => entered.complete();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(null),
          forceAudioRepositoryProvider.overrideWithValue(alerts),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([]);
      repo.read.complete();
      await ready;
      await container.read(conversationsProvider.future);
      final send = container
          .read(provider.notifier)
          .sendForceAudio(
            mediaUrl: 'https://example.invalid/a',
            sizeBytes: 100,
            durationMs: 1000,
          );
      final handled = expectLater(send, throwsA(isA<AuthFailure>()));
      await entered.future;
      (container.read(authControllerProvider.notifier) as _Auth).switchTo(
        'other',
      );
      await container.pump();
      await container.read(provider.future);
      repo.sendGate!.complete(_message('old-saved'));
      await handled;
      await container.pump();
      expect(alerts.created, 0);
      expect(container.read(provider).value!.messages, isEmpty);
    },
  );
  test(
    'force audio alert failure retains the saved message without a duplicate',
    () async {
      final repo = _Chat()
        ..conversationRows = [
          const Conversation(
            id: 'conv',
            peer: ChatPeer(id: 'peer', displayName: 'Peer'),
          ),
        ];
      final alerts = _ForceAudio()..failWithNetwork = true;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
          chatLocalStoreProvider.overrideWithValue(null),
          forceAudioRepositoryProvider.overrideWithValue(alerts),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final provider = chatThreadProvider('conv');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final ready = container.read(provider.future);
      await container.pump();
      repo.snapshot.complete([]);
      repo.read.complete();
      await ready;
      await container.read(conversationsProvider.future);
      final result = await container
          .read(provider.notifier)
          .sendForceAudio(
            mediaUrl: 'https://example.invalid/a',
            sizeBytes: 100,
            durationMs: 1000,
          );
      expect(result, isNull);
      expect(alerts.created, 1);
      expect(container.read(provider).value!.messages.map((m) => m.id), [
        'saved',
      ]);
    },
  );
  test(
    'mark-read error does not discard a successful server snapshot',
    () async {
      final repo = _Chat();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_Auth.new),
          chatRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repo.events.close();
      });
      final result = container.read(chatThreadProvider('conv').future);
      await container.pump();
      repo.snapshot.complete([_message('server')]);
      repo.read.completeError(StateError('mark read failed'));
      final state = await result;
      expect(state.offline, isFalse);
      expect(state.messages.single.id, 'server');
    },
  );
}
