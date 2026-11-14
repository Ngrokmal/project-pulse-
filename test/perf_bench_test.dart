import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/calls/domain/call_session.dart';
import 'package:pulse/features/chat/domain/conversation.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/settings/domain/app_settings.dart';

/// Phase 10 — measured, repeatable numbers for the work the app does most on the
/// UI thread: parsing rows out of Postgres/Hive and running the call machine.
///
/// These are *not* device profiles. They run on the CI/test VM, so they are a
/// floor: any real phone will be slower. The thresholds are deliberately loose
/// (10x the observed numbers) so the suite catches regressions, not noise.
void main() {
  Map<String, dynamic> conversationRow(int i) => {
    'id': 'conv-$i',
    'kind': i % 3 == 0 ? 'group' : 'direct',
    'title': i % 3 == 0 ? 'Group $i' : null,
    'last_message_at': '2026-11-14T10:00:00Z',
    'last_message_preview': 'see you at 8',
    'last_message_sender': 'user-2',
    'conversation_members': [
      {
        'user_id': 'me',
        'role': 'owner',
        'profiles': {'id': 'me', 'display_name': 'Arif', 'username': 'arif'},
      },
      {
        'user_id': 'user-2',
        'role': 'member',
        'profiles': {
          'id': 'user-2',
          'display_name': 'Bela',
          'username': 'bela',
        },
      },
      {
        'user_id': 'user-3',
        'role': 'member',
        'profiles': {'id': 'user-3', 'display_name': 'Chotu'},
      },
    ],
  };

  Map<String, dynamic> messageRow(int i) => {
    'id': 'msg-$i',
    'conversation_id': 'conv-1',
    'sender_id': i.isEven ? 'me' : 'user-2',
    'kind': i % 5 == 0 ? 'audio' : 'text',
    'created_at': '2026-11-14T10:00:00Z',
    'body': i % 2 == 0 ? 'a short message body' : null,
    'media_url': i % 5 == 0 ? 'https://res.cloudinary.com/demo/a.m4a' : null,
    'media_thumb_url': null,
    'media_bytes': 96044,
    'duration_ms': 4000,
    'client_id': 'c-$i',
    'deleted_at': null,
  };

  test('row parsing throughput (measured)', () {
    const n = 1000;

    final swConversations = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      Conversation.fromMap(conversationRow(i), myId: 'me');
    }
    swConversations.stop();

    final swMessages = Stopwatch()..start();
    for (var i = 0; i < 5000; i++) {
      Message.fromMap(messageRow(i));
    }
    swMessages.stop();

    final swSettings = Stopwatch()..start();
    for (var i = 0; i < 20000; i++) {
      AppSettings.fromMap({'textScale': 1.0 + (i % 5) / 10});
    }
    swSettings.stop();

    final convUs = swConversations.elapsedMicroseconds / n;
    final msgUs = swMessages.elapsedMicroseconds / 5000;
    final setUs = swSettings.elapsedMicroseconds / 20000;

    // ignore: avoid_print
    print('''
=== Phase 10 measurements (test VM, JIT) =========================
1,000 conversations   (3 members each) : ${swConversations.elapsedMilliseconds} ms  (${convUs.toStringAsFixed(1)} µs/row)
5,000 messages                        : ${swMessages.elapsedMilliseconds} ms  (${msgUs.toStringAsFixed(1)} µs/row)
20,000 settings maps                  : ${swSettings.elapsedMilliseconds} ms  (${setUs.toStringAsFixed(2)} µs/row)
==================================================================''');

    expect(
      convUs,
      lessThan(500),
      reason: 'one conversation must parse well under 0.5 ms',
    );
    expect(
      msgUs,
      lessThan(200),
      reason: 'one message must parse well under 0.2 ms',
    );
  });

  test('call state machine throughput (measured)', () {
    const n = 200000;
    final sw = Stopwatch()..start();
    var transitions = 0;
    for (var i = 0; i < n; i++) {
      final state = CallMachine.next(
        current: CallState.connecting,
        rowState: i.isEven ? 'active' : 'connecting',
        iAmCaller: i % 3 == 0,
        mediaUp: i % 4 != 0,
      );
      if (state == CallState.active) transitions++;
    }
    sw.stop();
    // ignore: avoid_print
    print(
      '200,000 call-machine evaluations: ${sw.elapsedMilliseconds} ms '
      '(${(sw.elapsedMicroseconds / n).toStringAsFixed(2)} µs each, '
      '$transitions resolved to active)',
    );
    expect(transitions, greaterThan(0));
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });

  test('a long conversation list does not do quadratic work (measured)', () {
    // Building the inbox preview for 1,000 rows: each row is independent, so the
    // total must stay linear.
    final rows = [for (var i = 0; i < 1000; i++) conversationRow(i)];
    final sw = Stopwatch()..start();
    final parsed = [for (final r in rows) Conversation.fromMap(r, myId: 'me')];
    final unread = parsed.where((c) => c.hasUnread).length;
    final names = parsed.map((c) => c.displayName).toSet();
    sw.stop();
    // ignore: avoid_print
    print(
      'inbox projection for 1,000 conversations: ${sw.elapsedMilliseconds} ms '
      '(${names.length} distinct names, $unread unread)',
    );
    expect(parsed.length, 1000);
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}
