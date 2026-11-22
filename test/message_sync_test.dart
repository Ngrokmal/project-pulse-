import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/chat/domain/message_sync.dart';

Message message(String id, {String conversation = 'c'}) => Message(
  id: id,
  conversationId: conversation,
  senderId: 'sender',
  kind: MessageKind.text,
  body: id,
  createdAt: DateTime.utc(2026),
);

class FakeSource implements MessageChangeSource {
  FakeSource(this.events);
  final List<MessageChange> events;
  final calls = <int>[];
  bool fail = false;
  @override
  Future<List<MessageChange>> changes(
    String conversationId,
    int after,
    int limit,
  ) async {
    calls.add(after);
    if (fail) throw StateError('network');
    return events.where((event) => event.revision > after).take(limit).toList();
  }
}

class FakeStore implements MessageChangeStore {
  final cursors = <String, int>{};
  final rows = <String, Map<String, Message>>{};
  bool failCommit = false;
  bool compete = false;
  String key(String owner, String conversation) => '$owner/$conversation';
  @override
  Future<int> revision(String ownerId, String conversationId) async =>
      cursors[key(ownerId, conversationId)] ?? 0;
  @override
  Future<bool> applyAtomically({
    required String ownerId,
    required String conversationId,
    required int expectedRevision,
    required List<MessageChange> changes,
  }) async {
    final k = key(ownerId, conversationId);
    if (compete) {
      compete = false;
      return false;
    }
    if ((cursors[k] ?? 0) != expectedRevision) return false;
    if (failCommit) throw StateError('disk');
    final updated = Map<String, Message>.of(rows[k] ?? {});
    for (final event in changes) {
      if (event.message case final m?) updated[m.id] = m;
      if (event.deletedId case final id?) updated.remove(id);
    }
    rows[k] = updated;
    cursors[k] = changes.last.revision;
    return true;
  }
}

void main() {
  test(
    'catches up over more than one hundred revisions, including delete',
    () async {
      final source = FakeSource([
        for (var i = 1; i <= 205; i++)
          MessageChange.upsert(revision: i, message: message('$i')),
        const MessageChange.delete(revision: 206, messageId: '3'),
      ]);
      final store = FakeStore();
      expect(
        await MessageCatchUp(
          source,
          store,
        ).run(ownerId: 'a', conversationId: 'c'),
        isTrue,
      );
      expect(source.calls, [0, 100, 200, 206]);
      expect(store.cursors['a/c'], 206);
      expect(store.rows['a/c']!.length, 204);
      expect(store.rows['a/c']!.containsKey('3'), isFalse);
    },
  );
  test('missing revision is rejected without committing that page', () async {
    final source = FakeSource([
      MessageChange.upsert(revision: 2, message: message('2')),
    ]);
    final store = FakeStore();
    await expectLater(
      MessageCatchUp(source, store).run(ownerId: 'a', conversationId: 'c'),
      throwsA(isA<MessageSyncProtocolException>()),
    );
    expect(store.cursors, isEmpty);
  });
  test('disk or network failure never advances a cursor', () async {
    final source = FakeSource([
      MessageChange.upsert(revision: 1, message: message('1')),
    ]);
    final store = FakeStore()..failCommit = true;
    await expectLater(
      MessageCatchUp(source, store).run(ownerId: 'a', conversationId: 'c'),
      throwsStateError,
    );
    expect(store.cursors, isEmpty);
    store.failCommit = false;
    source.fail = true;
    await expectLater(
      MessageCatchUp(source, store).run(ownerId: 'a', conversationId: 'c'),
      throwsStateError,
    );
    expect(store.cursors, isEmpty);
  });
  test(
    'compare-and-swap failure refetches instead of applying stale batch',
    () async {
      final source = FakeSource([
        MessageChange.upsert(revision: 1, message: message('1')),
      ]);
      final store = FakeStore()..compete = true;
      expect(
        await MessageCatchUp(
          source,
          store,
        ).run(ownerId: 'a', conversationId: 'c'),
        isTrue,
      );
      expect(source.calls, [0, 0, 1]);
    },
  );
  test(
    'wrong conversation is rejected and account cursors are separate',
    () async {
      final source = FakeSource([
        MessageChange.upsert(
          revision: 1,
          message: message('1', conversation: 'other'),
        ),
      ]);
      final store = FakeStore();
      await expectLater(
        MessageCatchUp(source, store).run(ownerId: 'a', conversationId: 'c'),
        throwsA(isA<MessageSyncProtocolException>()),
      );
      expect(store.cursors, isEmpty);
      source.events[0] = MessageChange.upsert(
        revision: 1,
        message: message('1'),
      );
      await MessageCatchUp(
        source,
        store,
      ).run(ownerId: 'a', conversationId: 'c');
      expect(await store.revision('b', 'c'), 0);
    },
  );
  test('bounded catch-up resumes from committed revision', () async {
    final source = FakeSource([
      for (var i = 1; i <= 3; i++)
        MessageChange.upsert(revision: i, message: message('$i')),
    ]);
    final store = FakeStore();
    final sync = MessageCatchUp(source, store, pageSize: 1);
    expect(
      await sync.run(ownerId: 'a', conversationId: 'c', maxPages: 2),
      isFalse,
    );
    expect(store.cursors['a/c'], 2);
    expect(
      await sync.run(ownerId: 'a', conversationId: 'c', maxPages: 2),
      isTrue,
    );
    expect(store.cursors['a/c'], 3);
  });
}
