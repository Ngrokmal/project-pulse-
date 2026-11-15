@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/chat/data/supabase_chat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// End-to-end proof through the app's *own* repository code, against the live
/// project: this is the test that would have caught the inbox failing with
/// `PGRST200 … relationship between 'conversation_members' and 'profiles'`.
///
/// It needs a real session, so it skips itself when the environment does not
/// provide one (CI runs the offline suites instead):
///
///   SUPABASE_URL=… SUPABASE_ANON_KEY=… PULSE_TEST_EMAIL_A=… \
///   PULSE_TEST_PASSWORD=… flutter test test/live_repository_test.dart --tags live
void main() {
  final env = Platform.environment;
  final url = env['SUPABASE_URL'];
  final anon = env['SUPABASE_ANON_KEY'];
  final email = env['PULSE_TEST_EMAIL_A'];
  final password = env['PULSE_TEST_PASSWORD'];
  final configured =
      url != null && anon != null && email != null && password != null;

  test('the inbox loads through the real repository', () async {
    if (!configured) {
      // ignore: avoid_print
      print('skipped: no live credentials in the environment');
      return;
    }

    final client = SupabaseClient(url, anon);
    final auth = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    // ignore: avoid_print
    print('signed in as ${auth.user?.email}');

    final repo = SupabaseChatRepository(client);
    final conversations = await repo.conversations();
    // ignore: avoid_print
    print('conversations returned: ${conversations.length}');
    for (final c in conversations.take(5)) {
      // ignore: avoid_print
      print(
        '  ${c.isGroup ? '[group]' : '[direct]'} ${c.displayName} '
        '(${c.subtitleLabel}) last="${c.lastMessagePreview ?? '-'}" '
        'unread=${c.unreadCount}',
      );
    }

    // Every returned row must be usable by the UI: a name, and for direct
    // chats a peer id (otherwise the row would be dropped by the screen).
    for (final c in conversations) {
      expect(c.displayName.trim(), isNotEmpty);
      if (!c.isGroup) expect(c.peer.id, isNotEmpty);
    }

    final people = await repo.people();
    // ignore: avoid_print
    print('people available: ${people.length}');

    await client.auth.signOut();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
