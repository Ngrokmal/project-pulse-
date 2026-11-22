import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pulse/features/auth/application/auth_controller.dart';
import 'package:pulse/features/auth/domain/auth_repository.dart';
import 'package:pulse/features/chat/application/chat_controller.dart';
import 'package:pulse/features/chat/data/chat_local_store.dart';
import 'package:pulse/features/chat/data/supabase_chat_repository.dart';
import 'package:hive_ce/hive.dart';
import 'package:pulse/features/chat/application/chat_journal_sync.dart';
import 'package:pulse/features/chat/data/hive_message_sync_store.dart';
import 'package:pulse/features/chat/data/supabase_message_change_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _ManagedAuth extends AuthController {
  _ManagedAuth(this.id);
  final String id;
  @override
  AuthState build() => AuthSignedIn(PulseUser(id: id, email: null));
}

void main() {
  final env = Platform.environment;
  final enabled = env['PULSE_MANAGED_JOURNAL_TEST'] == '1';
  test(
    'managed journal catches up multiple pages and hard deletes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'pulse-managed-journal-',
      );
      Hive.init(dir.path);
      final box = await Hive.openBox<String>(
        'sync',
        encryptionCipher: HiveAesCipher(Hive.generateSecureKey()),
      );
      final client = SupabaseClient(
        env['PULSE_TEST_URL']!,
        env['PULSE_TEST_ANON']!,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      addTearDown(() async {
        await client.dispose();
        await Hive.close();
        await dir.delete(recursive: true);
      });
      await client.auth.signInWithPassword(
        email: env['PULSE_TEST_USER']!,
        password: env['PULSE_TEST_PASSWORD']!,
      );
      final owner = client.auth.currentUser!.id;
      final conv = env['PULSE_TEST_CONVERSATION']!;
      final conversations = await SupabaseChatRepository(client)
          .conversations();
      expect(
        conversations.any((conversation) => conversation.id == conv),
        isTrue,
      );
      final store = HiveMessageSyncStore(box);
      final source = SupabaseMessageChangeSource(client, owner);
      final sync = ChatJournalSyncImpl(
        source,
        store,
        pageSize: 100,
        markRevision: source.markReadRevision,
      );
      final first = (await sync.catchUp(owner, conv)).messages;
      expect(first.length, 125);
      expect(await store.revision(owner, conv), 125);
      final snapshotKey =
          'sync:v1:${base64Url.encode(utf8.encode(owner))}:${base64Url.encode(utf8.encode(conv))}';
      await box.put(snapshotKey, '{damaged synthetic payload');
      await box.flush();
      final recovered = await sync.catchUp(owner, conv);
      expect(recovered.revision, 125);
      expect(recovered.messages, hasLength(125));
      expect(
        box.keys.whereType<String>().where(
          (key) => key.startsWith('sync_quarantine:v1:'),
        ),
        hasLength(1),
      );
      await sync.markRead(conv, 125);
      final deleted = first.first;
      expect(deleted.creationRevision, isNotNull);
      await client.from('messages').delete().eq('id', deleted.id);
      await client.from('messages').insert({
        'conversation_id': conv,
        'sender_id': owner,
        'body': 'after-reconnect',
        'client_id': 'integration-reconnect',
      });
      final beforeAck = await client
          .from('conversation_members')
          .select('last_read_revision')
          .eq('conversation_id', conv)
          .eq('user_id', owner)
          .single();
      expect(beforeAck['last_read_revision'], 125);
      final second = (await sync.catchUp(owner, conv)).messages;
      expect(second.length, 125);
      expect(second.any((m) => m.id == deleted.id), isFalse);
      expect(second.any((m) => m.body == 'after-reconnect'), isTrue);
      expect(await store.revision(owner, conv), 127);
      await sync.markRead(conv, 127);
      await sync.markRead(conv, 125);
      final afterAck = await client
          .from('conversation_members')
          .select('last_read_revision')
          .eq('conversation_id', conv)
          .eq('user_id', owner)
          .single();
      expect(afterAck['last_read_revision'], 127);
      await expectLater(
        sync.markRead(conv, 128),
        throwsA(isA<PostgrestException>()),
      );

      final outbox = await Hive.openBox<String>(
        'outbox',
        encryptionCipher: HiveAesCipher(Hive.generateSecureKey()),
      );
      final local = ChatLocalStore.forTesting(box, outbox);
      ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(() => _ManagedAuth(owner)),
          chatLocalStoreProvider.overrideWithValue(local),
          chatRepositoryProvider.overrideWithValue(
            SupabaseChatRepository(client),
          ),
          chatJournalSyncProvider.overrideWith((ref, id) => sync),
        ],
      );
      Future<void> waitFor(
        ProviderContainer c,
        bool Function(ChatThreadState) matches,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          await c.pump();
          final value = c.read(chatThreadProvider(conv)).value;
          if (value != null && matches(value)) return;
        }
        fail('thread did not reach expected journal state');
      }

      var container = makeContainer();
      var sub = container.listen(chatThreadProvider(conv), (_, _) {});
      await container.read(chatThreadProvider(conv).future);
      await waitFor(container, (s) => s.messages.length == 125);
      sub.close();
      container.dispose();
      final removed = second[1];
      await client.from('messages').delete().eq('id', removed.id);
      await client.from('messages').insert({
        'conversation_id': conv,
        'sender_id': owner,
        'body': 'thread-reconnect',
        'client_id': 'integration-thread-reconnect',
      });
      container = makeContainer();
      sub = container.listen(chatThreadProvider(conv), (_, _) {});
      addTearDown(() {
        sub.close();
        container.dispose();
      });
      await container.read(chatThreadProvider(conv).future);
      await waitFor(
        container,
        (s) =>
            s.messages.length == 125 &&
            s.messages.any((m) => m.body == 'thread-reconnect') &&
            !s.messages.any((m) => m.id == removed.id),
      );
      await client.from('messages').insert({
        'id': deleted.id,
        'conversation_id': conv,
        'sender_id': owner,
        'body': 'reused-id',
        'client_id': 'integration-reused-id',
      });
      final again = await sync.catchUp(owner, conv);
      final reincarnated = again.messages.singleWhere(
        (m) => m.id == deleted.id,
      );
      expect(reincarnated.body, 'reused-id');
      expect(
        reincarnated.creationRevision,
        greaterThan(deleted.creationRevision!),
      );
    },
    skip: enabled
        ? false
        : 'Managed integration requires disposable test project harness',
  );
}
