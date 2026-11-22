import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pulse/features/chat/data/hive_message_sync_store.dart';
import 'package:pulse/features/chat/application/chat_journal_sync.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/chat/domain/message_sync.dart';

Message msg(
  String id, {
  String conversation = 'c',
  DeliveryState delivery = DeliveryState.sent,
}) => Message(
  id: id,
  conversationId: conversation,
  senderId: 'sender',
  kind: MessageKind.text,
  body: 'body-$id',
  createdAt: DateTime.utc(2026),
  delivery: delivery,
);

class _Source implements MessageChangeSource {
  _Source(this.events);
  final List<MessageChange> events;
  @override
  Future<List<MessageChange>> changes(
    String conversationId,
    int after,
    int limit,
  ) async =>
      events.where((event) => event.revision > after).take(limit).toList();
}

class _Offline implements MessageChangeSource {
  @override
  Future<List<MessageChange>> changes(
    String conversationId,
    int after,
    int limit,
  ) async => throw StateError('offline');
}

void main() {
  late Directory dir;
  late Box<String> box;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pulse-hive-sync-');
    Hive.init(dir.path);
    box = await Hive.openBox<String>('sync');
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test(
    'malformed local snapshot is preserved and rebuilt from server',
    () async {
      const badKey = 'sync:v1:YQ==:Yw==';
      await box.put(badKey, 'private-invalid-json');
      final store = HiveMessageSyncStore(box);
      final sync = ChatJournalSyncImpl(
        _Source([MessageChange.upsert(revision: 1, message: msg('rebuilt'))]),
        store,
      );
      final snapshot = await sync.catchUp('a', 'c');
      expect(snapshot.revision, 1);
      expect(snapshot.messages.single.id, 'rebuilt');
      final quarantine = box.keys
          .whereType<String>()
          .where((k) => k.startsWith('sync_quarantine:v1:'))
          .toList();
      expect(quarantine, hasLength(1));
      expect(box.get(quarantine.single), 'private-invalid-json');
      expect(await store.quarantineMalformedSnapshot('a', 'c'), isFalse);
    },
  );
  test(
    'offline rebuild retains damaged bytes and cannot claim catch-up',
    () async {
      const key = 'sync:v1:YQ==:Yw==';
      await box.put(key, 'damaged');
      final store = HiveMessageSyncStore(box);
      await expectLater(
        ChatJournalSyncImpl(_Offline(), store).catchUp('a', 'c'),
        throwsStateError,
      );
      expect(await store.revision('a', 'c'), 0);
      final saved = box.keys.whereType<String>().where(
        (k) => k.startsWith('sync_quarantine:v1:'),
      );
      expect(saved, hasLength(1));
      expect(box.get(saved.single), 'damaged');
    },
  );
  test('cursor and rows survive reopen, updates and deletes', () async {
    var store = HiveMessageSyncStore(box);
    expect(
      await store.applyAtomically(
        ownerId: 'a',
        conversationId: 'c',
        expectedRevision: 0,
        changes: [
          MessageChange.upsert(revision: 1, message: msg('one')),
          MessageChange.upsert(revision: 2, message: msg('two')),
          const MessageChange.delete(revision: 3, messageId: 'one'),
        ],
      ),
      isTrue,
    );
    await Hive.close();
    Hive.init(dir.path);
    box = await Hive.openBox<String>('sync');
    store = HiveMessageSyncStore(box);
    expect(await store.revision('a', 'c'), 3);
    expect((await store.messages('a', 'c')).map((m) => m.id), ['two']);
    expect(await store.revision('b', 'c'), 0);
    expect(await store.messages('b', 'c'), isEmpty);
  });
  test(
    'paged catch-up persists more than 100 events in Hive across reopen',
    () async {
      final events = [
        for (var i = 1; i <= 205; i++)
          MessageChange.upsert(revision: i, message: msg('$i')),
        const MessageChange.delete(revision: 206, messageId: '3'),
      ];
      var store = HiveMessageSyncStore(box);
      final sync = MessageCatchUp(_Source(events), store);
      expect(
        await sync.run(ownerId: 'a', conversationId: 'c', maxPages: 2),
        isFalse,
      );
      expect(await store.revision('a', 'c'), 200);
      await Hive.close();
      Hive.init(dir.path);
      box = await Hive.openBox<String>('sync');
      store = HiveMessageSyncStore(box);
      expect(
        await MessageCatchUp(
          _Source(events),
          store,
        ).run(ownerId: 'a', conversationId: 'c'),
        isTrue,
      );
      expect(await store.revision('a', 'c'), 206);
      final rows = await store.messages('a', 'c');
      expect(rows, hasLength(204));
      expect(rows.any((m) => m.id == '3'), isFalse);
    },
  );
  test('competing commits using the same box cannot both win', () async {
    final a = HiveMessageSyncStore(box);
    final b = HiveMessageSyncStore(box);
    final results = await Future.wait([
      a.applyAtomically(
        ownerId: 'a',
        conversationId: 'c',
        expectedRevision: 0,
        changes: [MessageChange.upsert(revision: 1, message: msg('first'))],
      ),
      b.applyAtomically(
        ownerId: 'a',
        conversationId: 'c',
        expectedRevision: 0,
        changes: [MessageChange.upsert(revision: 1, message: msg('second'))],
      ),
    ]);
    expect(results.where((x) => x), hasLength(1));
    expect(await a.revision('a', 'c'), 1);
    expect(await a.messages('a', 'c'), hasLength(1));
  });
  test('invalid batch does not update cursor or messages', () async {
    final store = HiveMessageSyncStore(box);
    await expectLater(
      store.applyAtomically(
        ownerId: 'a',
        conversationId: 'c',
        expectedRevision: 0,
        changes: [
          MessageChange.upsert(revision: 1, message: msg('ok')),
          MessageChange.upsert(revision: 3, message: msg('gap')),
        ],
      ),
      throwsA(isA<MessageSyncProtocolException>()),
    );
    expect(await store.revision('a', 'c'), 0);
    expect(await store.messages('a', 'c'), isEmpty);
    await expectLater(
      store.applyAtomically(
        ownerId: 'a',
        conversationId: 'c',
        expectedRevision: 0,
        changes: [
          MessageChange.upsert(
            revision: 1,
            message: msg('wrong', conversation: 'other'),
          ),
        ],
      ),
      throwsA(isA<MessageSyncProtocolException>()),
    );
    expect(await store.revision('a', 'c'), 0);
  });
  test('corrupt data is retained and fails closed', () async {
    final store = HiveMessageSyncStore(box);
    await store.applyAtomically(
      ownerId: 'a',
      conversationId: 'c',
      expectedRevision: 0,
      changes: [MessageChange.upsert(revision: 1, message: msg('one'))],
    );
    final key = box.keys.single;
    await box.put(key, 'not-json');
    await expectLater(store.revision('a', 'c'), throwsFormatException);
    expect(box.get(key), 'not-json');
  });
  test(
    'rejects optimistic messages rather than persisting false confirmations',
    () async {
      final store = HiveMessageSyncStore(box);
      await expectLater(
        store.applyAtomically(
          ownerId: 'a',
          conversationId: 'c',
          expectedRevision: 0,
          changes: [
            MessageChange.upsert(
              revision: 1,
              message: msg('draft', delivery: DeliveryState.pending),
            ),
          ],
        ),
        throwsA(isA<MessageSyncProtocolException>()),
      );
      expect(await store.revision('a', 'c'), 0);
    },
  );
}
