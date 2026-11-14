import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/chat/domain/conversation.dart';

/// Phase 7 (groups): the client model has to mirror the SQL in
/// `supabase/migrations/0006_groups.sql` exactly — kind, title, member count and
/// my own role are what the UI uses to decide what it may show or offer.
void main() {
  const me = 'aaaaaaaa-0000-4000-8000-000000000001';
  const other = 'bbbbbbbb-0000-4000-8000-000000000002';

  Map<String, dynamic> groupMap({
    String? title = 'Trip to Cox’s Bazar',
    String myRole = 'owner',
    int members = 3,
  }) => {
    'id': 'c1',
    'kind': 'group',
    'title': title,
    'last_message_at': null,
    'last_message_preview': 'see you at 8',
    'last_message_sender': other,
    'conversation_members': [
      {
        'user_id': me,
        'role': myRole,
        'profiles': {'id': me, 'display_name': 'Arif', 'username': 'arif'},
      },
      {
        'user_id': other,
        'role': 'admin',
        'profiles': {'id': other, 'display_name': 'Bela', 'username': 'bela'},
      },
      for (var i = 2; i < members; i++)
        {
          'user_id': 'ccccc00$i',
          'role': 'member',
          'profiles': {'id': 'ccccc00$i', 'display_name': 'Guest $i'},
        },
    ],
  };

  group('Conversation.fromMap — groups', () {
    test('reads kind, title, member count and my role', () {
      final c = Conversation.fromMap(groupMap(), myId: me);
      expect(c.isGroup, isTrue);
      expect(c.kind, 'group');
      expect(c.title, 'Trip to Cox’s Bazar');
      expect(c.memberCount, 3);
      expect(c.myRole, GroupRole.owner);
      expect(c.displayName, 'Trip to Cox’s Bazar');
      expect(c.subtitleLabel, '3 members');
    });

    test('a group with no title still has a usable name', () {
      final c = Conversation.fromMap(groupMap(title: '   '), myId: me);
      expect(c.displayName, 'Group');
      expect(c.initials, 'G');
    });

    test('singular member count reads correctly', () {
      final c = Conversation.fromMap(
        {
          ...groupMap(),
          'conversation_members': [
            {
              'user_id': me,
              'role': 'owner',
              'profiles': {'id': me, 'display_name': 'Arif'},
            },
          ],
        },
        myId: me,
      );
      expect(c.memberCount, 1);
      expect(c.subtitleLabel, '1 member');
    });

    test('a group survives having no other member (peer stays empty)', () {
      final c = Conversation.fromMap(
        {
          ...groupMap(),
          'conversation_members': [
            {
              'user_id': me,
              'role': 'owner',
              'profiles': {'id': me, 'display_name': 'Arif'},
            },
          ],
        },
        myId: me,
      );
      expect(c.peer.id, isEmpty);
      expect(c.isGroup, isTrue);
    });

    test('direct chats keep the peer name and show no role', () {
      final c = Conversation.fromMap({
        'id': 'd1',
        'kind': 'direct',
        'title': null,
        'conversation_members': [
          {
            'user_id': me,
            'role': 'member',
            'profiles': {'id': me, 'display_name': 'Arif'},
          },
          {
            'user_id': other,
            'role': 'member',
            'profiles': {'id': other, 'display_name': 'Bela', 'username': 'bela'},
          },
        ],
      }, myId: me);
      expect(c.isGroup, isFalse);
      expect(c.displayName, 'Bela');
      expect(c.subtitleLabel, '@bela');
      expect(c.myRole, GroupRole.member);
    });

    test('missing kind defaults to direct (older rows)', () {
      final c = Conversation.fromMap({
        'id': 'd2',
        'conversation_members': [
          {
            'user_id': other,
            'profiles': {'id': other, 'display_name': 'Bela'},
          },
        ],
      }, myId: me);
      expect(c.isGroup, isFalse);
      expect(c.myRole, isNull);
    });
  });

  group('GroupRole — what the UI is allowed to offer', () {
    test('parses the three roles SQL allows and rejects anything else', () {
      expect(GroupRole.parse('owner'), GroupRole.owner);
      expect(GroupRole.parse('admin'), GroupRole.admin);
      expect(GroupRole.parse('member'), GroupRole.member);
      expect(GroupRole.parse('superuser'), isNull);
      expect(GroupRole.parse(null), isNull);
    });

    test('owners and admins manage members, plain members do not', () {
      expect(GroupRole.owner.canManageMembers, isTrue);
      expect(GroupRole.admin.canManageMembers, isTrue);
      expect(GroupRole.member.canManageMembers, isFalse);
      expect(GroupRole.owner.isOwner, isTrue);
      expect(GroupRole.admin.isOwner, isFalse);
    });

    test('role names sent to the RPC are the SQL literals', () {
      expect(GroupRole.owner.name, 'owner');
      expect(GroupRole.admin.name, 'admin');
      expect(GroupRole.member.name, 'member');
    });
  });
}
