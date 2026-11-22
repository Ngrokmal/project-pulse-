import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pulse/features/chat/data/hive_message_sync_store.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/chat/domain/message_sync.dart';

void main() {
  test(
    'experimental sync snapshot round trips in a Hive encrypted box',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'pulse-hive-encryption-',
      );
      final key = Hive.generateSecureKey();
      const secret = 'local plaintext canary 7def13b8';
      try {
        Hive.init(dir.path);
        var box = await Hive.openBox<String>(
          'encrypted_sync',
          encryptionCipher: HiveAesCipher(key),
        );
        var store = HiveMessageSyncStore(box);
        await store.applyAtomically(
          ownerId: 'a',
          conversationId: 'c',
          expectedRevision: 0,
          changes: [
            MessageChange.upsert(
              revision: 1,
              message: Message(
                id: 'row',
                conversationId: 'c',
                senderId: 'a',
                kind: MessageKind.text,
                body: secret,
                createdAt: DateTime.utc(2026),
              ),
            ),
          ],
        );
        await Hive.close();
        final file = File('${dir.path}/encrypted_sync.hive');
        final bytes = await file.readAsBytes();
        expect(latin1.decode(bytes), isNot(contains(secret)));
        Hive.init(dir.path);
        box = await Hive.openBox<String>(
          'encrypted_sync',
          encryptionCipher: HiveAesCipher(key),
        );
        store = HiveMessageSyncStore(box);
        expect(await store.revision('a', 'c'), 1);
        expect((await store.messages('a', 'c')).single.body, secret);
      } finally {
        await Hive.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
