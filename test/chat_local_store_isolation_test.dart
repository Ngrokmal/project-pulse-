import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pulse/features/chat/data/chat_local_store.dart';
import 'package:pulse/features/chat/domain/message.dart';

void main() {
  late Directory dir;
  late Box<String> cache;
  late Box<String> outbox;
  late ChatLocalStore root;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pulse-chat-test-');
    Hive.init(dir.path);
    cache = await Hive.openBox<String>('cache');
    outbox = await Hive.openBox<String>('outbox');
    root = ChatLocalStore.forTesting(cache, outbox);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  PendingMessage pending(String id, String body) => PendingMessage(
    clientId: id,
    conversationId: 'shared',
    body: body,
    queuedAt: DateTime.utc(2026),
  );
  Message message(String id, String body) => Message(
    id: id,
    conversationId: 'shared',
    senderId: 'sender',
    kind: MessageKind.text,
    body: body,
    createdAt: DateTime.utc(2026),
  );

  test(
    'two accounts have separate cache and outbox for the same conversation',
    () async {
      final a = root.forUser('a');
      final b = root.forUser('b');
      a.cacheMessages('shared', [message('1', 'private-a')]);
      b.cacheMessages('shared', [message('2', 'private-b')]);
      await a.enqueue(pending('same-client', 'draft-a'));
      await b.enqueue(pending('same-client', 'draft-b'));
      expect(a.cachedMessages('shared').single.body, 'private-a');
      expect(b.cachedMessages('shared').single.body, 'private-b');
      expect(a.pending().single.body, 'draft-a');
      expect(b.pending().single.body, 'draft-b');
      await a.dequeue('same-client');
      expect(a.pending(), isEmpty);
      expect(b.pending().single.body, 'draft-b');
    },
  );
  test(
    'clearing one account preserves the other and unowned legacy entries',
    () async {
      final a = root.forUser('a');
      final b = root.forUser('b');
      await outbox.put('legacy-client-id', 'unowned legacy draft');
      await cache.put('legacy-conversation-id', 'unowned legacy cache');
      await a.enqueue(pending('a-client', 'draft-a'));
      await b.enqueue(pending('b-client', 'draft-b'));
      a.cacheMessages('shared', [message('a', 'a')]);
      b.cacheMessages('shared', [message('b', 'b')]);
      await a.clear();
      expect(a.pending(), isEmpty);
      expect(a.cachedMessages('shared'), isEmpty);
      expect(b.pending().single.body, 'draft-b');
      expect(b.cachedMessages('shared').single.body, 'b');
      expect(outbox.get('legacy-client-id'), 'unowned legacy draft');
      expect(cache.get('legacy-conversation-id'), 'unowned legacy cache');
    },
  );
  test('queued text survives closing and reopening the boxes', () async {
    await root.forUser('a').enqueue(pending('durable-client', 'draft'));
    await Hive.close();
    Hive.init(dir.path);
    cache = await Hive.openBox<String>('cache');
    outbox = await Hive.openBox<String>('outbox');
    root = ChatLocalStore.forTesting(cache, outbox);
    expect(root.forUser('a').pending().single.body, 'draft');
    expect(root.forUser('b').pending(), isEmpty);
  });
  test(
    'outbox is reconciled only against an exact confirmed own message',
    () async {
      final a = root.forUser('a');
      final b = root.forUser('b');
      await a.enqueue(pending('id-one', 'draft'));
      await b.enqueue(pending('id-one', 'draft'));
      Message row({
        String sender = 'a',
        String text = 'draft',
        String conversation = 'shared',
        DeliveryState delivery = DeliveryState.sent,
      }) => Message(
        id: 'server',
        conversationId: conversation,
        senderId: sender,
        kind: MessageKind.text,
        body: text,
        clientId: 'id-one',
        createdAt: DateTime.utc(2026),
        delivery: delivery,
      );
      expect(
        await a.reconcileConfirmed([
          row(sender: 'b'),
          row(text: 'wrong'),
          row(conversation: 'elsewhere'),
          row(delivery: DeliveryState.pending),
        ]),
        0,
      );
      expect(a.pending(), hasLength(1));
      expect(await a.reconcileConfirmed([row()]), 1);
      expect(a.pending(), isEmpty);
      expect(b.pending(), hasLength(1));
    },
  );
  test('ownerless sent entries reconcile only on exact server evidence; unsent remains hidden', () async {
    final a = root.forUser('a');
    await outbox.put(
      'known',
      jsonEncode(pending('known', 'already sent').toMap()),
    );
    await outbox.put(
      'unsent',
      jsonEncode(pending('unsent', 'private unsent').toMap()),
    );
    Message row({
      String sender = 'a',
      String body = 'already sent',
      String conversation = 'shared',
    }) => Message(
      id: 'row',
      clientId: 'known',
      conversationId: conversation,
      senderId: sender,
      kind: MessageKind.text,
      body: body,
      createdAt: DateTime.utc(2026),
    );
    expect(
      await a.reconcileLegacyConfirmed([
        row(sender: 'b'),
        row(body: 'different'),
        row(conversation: 'elsewhere'),
      ]),
      0,
    );
    expect(outbox.containsKey('known'), isTrue);
    expect(await a.reconcileLegacyConfirmed([row()]), 1);
    expect(outbox.containsKey('known'), isFalse);
    expect(outbox.containsKey('unsent'), isTrue);
    expect(a.pending(), isEmpty);
    expect(root.forUser('b').pending(), isEmpty);
  });
  test('unscoped operations fail instead of leaking data', () {
    expect(() => root.pending(), throwsStateError);
    expect(() => root.forUser(''), throwsArgumentError);
  });
  test('pending messages are not cached as confirmed', () {
    final a = root.forUser('a');
    final pendingMessage = Message(
      id: 'pending',
      conversationId: 'shared',
      senderId: 'a',
      kind: MessageKind.text,
      createdAt: DateTime.utc(2026),
      body: 'draft',
      delivery: DeliveryState.pending,
    );
    a.cacheMessages('shared', [pendingMessage]);
    expect(a.cachedMessages('shared'), isEmpty);
  });
}
