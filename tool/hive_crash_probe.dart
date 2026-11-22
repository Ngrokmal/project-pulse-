import 'dart:async';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:pulse/features/chat/data/hive_message_sync_store.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/chat/domain/message_sync.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('mode and directory required');
  Hive.init(args[1]);
  final box = await Hive.openBox<String>(
    'crash_probe',
    encryptionCipher: HiveAesCipher(List<int>.generate(32, (i) => i)),
    crashRecovery: args[0] == 'recover-copy',
  );
  final store = HiveMessageSyncStore(box);
  if (args[0] == 'write') {
    final message = Message(
      id: 'synthetic',
      conversationId: 'conversation',
      senderId: 'owner',
      kind: MessageKind.text,
      body: 'test',
      createdAt: DateTime.utc(2026),
    );
    final saved = await store.applyAtomically(
      ownerId: 'owner',
      conversationId: 'conversation',
      expectedRevision: 0,
      changes: [MessageChange.upsert(revision: 1, message: message)],
    );
    if (!saved) throw StateError('not saved');
    stdout.writeln('FLUSHED');
    await stdout.flush();
    await Completer<void>().future;
  } else if (args[0] == 'write-race') {
    final changes = <MessageChange>[];
    for (var i = 2; i <= 1001; i++) {
      changes.add(
        MessageChange.upsert(
          revision: i,
          message: Message(
            id: 'row-$i',
            conversationId: 'conversation',
            senderId: 'owner',
            kind: MessageKind.text,
            body: List.filled(3000, 'x').join(),
            createdAt: DateTime.utc(2026),
          ),
        ),
      );
    }
    stdout.writeln('WRITING');
    await stdout.flush();
    await store.applyAtomically(
      ownerId: 'owner',
      conversationId: 'conversation',
      expectedRevision: 1,
      changes: changes,
    );
    stdout.writeln('DONE');
    await stdout.flush();
    await Completer<void>().future;
  } else if (args[0] == 'recover-copy') {
    final snapshot = await store.snapshot('owner', 'conversation');
    if (snapshot.revision != 1 || snapshot.messages.length != 1) {
      throw StateError('unexpected recovered state');
    }
    stdout.writeln('RECOVERED prior complete revision 1 from disposable copy');
    await Hive.close();
  } else if (args[0] == 'verify-race') {
    final snapshot = await store.snapshot('owner', 'conversation');
    if (!((snapshot.revision == 1 && snapshot.messages.length == 1) ||
        (snapshot.revision == 1001 && snapshot.messages.length == 1001))) {
      throw StateError('partial cursor/data mismatch');
    }
    stdout.writeln('PASS cursor/data consistent revision ${snapshot.revision}');
    await Hive.close();
  } else if (args[0] == 'verify') {
    final snapshot = await store.snapshot('owner', 'conversation');
    if (snapshot.revision != 1 ||
        snapshot.messages.length != 1 ||
        snapshot.messages.single.body != 'test') {
      throw StateError('cursor/data mismatch');
    }
    stdout.writeln('PASS cursor and message survived process termination');
    await Hive.close();
  } else {
    throw ArgumentError('invalid mode');
  }
}
