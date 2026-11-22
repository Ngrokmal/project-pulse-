import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pulse/features/chat/data/encrypted_chat_boxes.dart';

class Vault implements ChatKeyVault {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (!failWrite) this.value = value;
  }
}

void main() {
  late Directory dir;
  late Vault vault;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pulse-secure-');
    Hive.init(dir.path);
    vault = Vault();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test('copies old data, retains source, reopens encrypted boxes and does not replay old data', () async {
    final cache = await Hive.openBox<String>('chat_messages');
    final outbox = await Hive.openBox<String>('chat_outbox');
    await cache.put('legacy', 'legacy-sensitive-content');
    await outbox.put('legacy-draft', 'private-draft-content');
    final boxes = await openEncryptedChatBoxes(vault);
    expect(boxes.cache.get('legacy'), 'legacy-sensitive-content');
    expect(boxes.outbox.get('legacy-draft'), 'private-draft-content');
    expect(outbox.get('legacy-draft'), 'private-draft-content');
    await boxes.outbox.delete('legacy-draft');
    await Hive.close();
    expect(
      latin1.decode(
        await File('${dir.path}/chat_outbox_secure_v1.hive').readAsBytes(),
      ),
      isNot(contains('private-draft-content')),
    );
    Hive.init(dir.path);
    final reopened = await openEncryptedChatBoxes(vault);
    expect(reopened.outbox.get('legacy-draft'), isNull);
    expect(reopened.cache.get('legacy'), 'legacy-sensitive-content');
  });
  test('missing key with existing encrypted data fails closed', () async {
    await openEncryptedChatBoxes(vault);
    await Hive.close();
    Hive.init(dir.path);
    vault.value = null;
    await expectLater(openEncryptedChatBoxes(vault), throwsStateError);
    expect(vault.value, isNull);
  });
  test('failed vault write never creates encrypted boxes', () async {
    vault.failWrite = true;
    await expectLater(openEncryptedChatBoxes(vault), throwsStateError);
    expect(await Hive.boxExists('chat_messages_secure_v1'), isFalse);
    expect(await Hive.boxExists('chat_outbox_secure_v1'), isFalse);
  });
  test('incorrect valid key cannot destroy encrypted data', () async {
    final original = await openEncryptedChatBoxes(vault);
    await original.outbox.put('draft', 'must survive');
    await original.outbox.flush();
    final key = vault.value;
    await Hive.close();
    Hive.init(dir.path);
    vault.value = base64Encode(Hive.generateSecureKey());
    await expectLater(openEncryptedChatBoxes(vault), throwsA(anything));
    await Hive.close();
    Hive.init(dir.path);
    vault.value = key;
    final reopened = await openEncryptedChatBoxes(vault);
    expect(reopened.outbox.get('draft'), 'must survive');
  });
  test('malformed key fails closed', () async {
    vault.value = 'not-valid';
    await expectLater(openEncryptedChatBoxes(vault), throwsStateError);
    expect(await Hive.boxExists('chat_messages_secure_v1'), isFalse);
  });
}
