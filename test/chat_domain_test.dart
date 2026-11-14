import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/chat/domain/conversation.dart';
import 'package:pulse/features/chat/domain/message.dart';

void main() {
  group(
    'Message validation mirrors the DB CHECK (body <= 4000, not blank)',
    () {
      test('accepts a normal message', () {
        expect(Message.validateBody('Hello there'), isNull);
      });

      test('rejects blank and whitespace-only bodies', () {
        expect(Message.validateBody(''), isNotNull);
        expect(Message.validateBody('   \n  '), isNotNull);
      });

      test('rejects bodies over 4000 characters', () {
        expect(Message.validateBody('x' * 4000), isNull);
        expect(Message.validateBody('x' * 4001), isNotNull);
      });
    },
  );

  group('Message mapping', () {
    test('round-trips through the Hive cache format', () {
      final original = Message(
        id: 'm1',
        conversationId: 'c1',
        senderId: 'u1',
        kind: MessageKind.text,
        createdAt: DateTime.utc(2026, 11, 14, 12, 30),
        body: 'hey',
        clientId: 'client-1',
      );
      final restored = Message.fromMap(original.toMap());
      expect(restored.id, original.id);
      expect(restored.body, 'hey');
      expect(restored.kind, MessageKind.text);
      expect(restored.clientId, 'client-1');
      expect(restored.createdAt.toUtc(), original.createdAt.toUtc());
      expect(restored.delivery, DeliveryState.sent);
    });

    test('unknown enum values fall back to text instead of crashing', () {
      expect(messageKindFromDb('future_kind'), MessageKind.text);
      expect(messageKindFromDb(null), MessageKind.text);
      expect(messageKindFromDb('force_audio'), MessageKind.forceAudio);
    });

    test('previews are meaningful for every kind', () {
      Message m(MessageKind kind, [String? body]) => Message(
        id: 'x',
        conversationId: 'c',
        senderId: 'u',
        kind: kind,
        createdAt: DateTime.now(),
        body: body,
      );
      expect(m(MessageKind.text, 'yo').preview, 'yo');
      expect(m(MessageKind.image).preview, 'Photo');
      expect(m(MessageKind.video).preview, 'Video');
      expect(m(MessageKind.audio).preview, 'Voice message');
      expect(m(MessageKind.forceAudio).preview, 'Force audio alert');
    });
  });

  group('Conversation.fromMap', () {
    Map<String, dynamic> row(String peerId, String displayName) => {
      'id': 'conv-1',
      'last_message_at': '2026-11-14T12:00:00Z',
      'last_message_preview': 'Hi',
      'last_message_sender': 'me',
      'conversation_members': [
        {
          'user_id': 'me',
          'profiles': {'id': 'me', 'display_name': 'Me'},
        },
        {
          'user_id': peerId,
          'profiles': {
            'id': peerId,
            'display_name': displayName,
            'username': 'bela',
          },
        },
      ],
    };

    test('picks the other participant as the peer, never myself', () {
      final c = Conversation.fromMap(row('u2', 'Bela'), myId: 'me');
      expect(c.peer.id, 'u2');
      expect(c.peer.displayName, 'Bela');
      expect(c.peer.username, 'bela');
      expect(c.lastMessagePreview, 'Hi');
      expect(c.isMineLast('me'), isTrue);
      expect(c.isMineLast('u2'), isFalse);
    });

    test('peer initials come from the display name', () {
      expect(ChatPeer(id: 'x', displayName: 'Bela Das').initials, 'BD');
      expect(ChatPeer(id: 'x', displayName: 'Bela').initials, 'B');
      expect(ChatPeer(id: 'x', displayName: '   ').initials, '?');
    });

    test('a member with no profile row does not crash the list', () {
      final broken = row('u2', 'Bela');
      (broken['conversation_members'] as List).removeLast();
      final c = Conversation.fromMap(broken, myId: 'me');
      expect(c.peer.id, '');
      expect(c.peer.displayName, 'Pulse user');
    });
  });
}
