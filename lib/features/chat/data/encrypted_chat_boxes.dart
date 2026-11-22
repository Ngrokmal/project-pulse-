import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'hive_box_copy.dart';

/// Secure key storage is platform-backed. A missing or malformed key must not
/// cause existing ciphertext to be overwritten with a newly generated key.
abstract interface class ChatKeyVault {
  Future<String?> read();
  Future<void> write(String value);
}

class PlatformChatKeyVault implements ChatKeyVault {
  const PlatformChatKeyVault();
  static const _name = 'pulse_chat_hive_key_v1';
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _name);
  @override
  Future<void> write(String value) => _storage.write(key: _name, value: value);
}

class EncryptedChatBoxes {
  const EncryptedChatBoxes(this.cache, this.outbox);
  final Box<String> cache;
  final Box<String> outbox;
}

/// Call exactly once at startup, before any chat writers exist. Old plaintext
/// boxes are retained for recovery: encryption is not complete until a safe
/// retention/deletion policy is implemented and tested on real devices.
Future<EncryptedChatBoxes> openEncryptedChatBoxes(ChatKeyVault vault) async {
  const cacheName = 'chat_messages_secure_v1';
  const outboxName = 'chat_outbox_secure_v1';
  const marker = '__pulse_encrypted_migration_v1__';
  var stored = await vault.read();
  if (stored == null) {
    if (await Hive.boxExists(cacheName) || await Hive.boxExists(outboxName)) {
      throw StateError('Encrypted chat data exists but its key is unavailable');
    }
    stored = base64Encode(Hive.generateSecureKey());
    await vault.write(stored);
    if (await vault.read() != stored) {
      throw StateError('Secure chat key could not be verified');
    }
  }
  final List<int> key;
  try {
    key = base64Decode(stored);
  } on FormatException {
    throw StateError('Invalid secure chat key');
  }
  if (key.length != 32) throw StateError('Invalid secure chat key');
  final cache = await Hive.openBox<String>(
    cacheName,
    encryptionCipher: HiveAesCipher(key),
    crashRecovery: false,
  );
  final outbox = await Hive.openBox<String>(
    outboxName,
    encryptionCipher: HiveAesCipher(key),
    crashRecovery: false,
  );
  if (cache.get(marker) != 'complete') {
    final legacyCache = await Hive.openBox<String>(
      'chat_messages',
      crashRecovery: false,
    );
    final legacyOutbox = await Hive.openBox<String>(
      'chat_outbox',
      crashRecovery: false,
    );
    if (legacyCache.containsKey(marker)) {
      throw StateError('Migration marker conflict');
    }
    await copyHiveStringsWithoutDeleting(
      source: legacyCache,
      destination: cache,
    );
    await copyHiveStringsWithoutDeleting(
      source: legacyOutbox,
      destination: outbox,
    );
    await cache.put(marker, 'complete');
    await cache.flush();
  }
  return EncryptedChatBoxes(cache, outbox);
}
