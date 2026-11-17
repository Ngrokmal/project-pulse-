import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/theme/app_colors.dart';
import 'package:pulse/features/chat/domain/conversation.dart';
import 'package:pulse/features/chat/domain/message.dart';
import 'package:pulse/features/inbox/presentation/widgets/inbox_header.dart';
import 'package:pulse/features/media/domain/media_labels.dart';
import 'package:pulse/features/presence/domain/presence.dart';

/// The round's contracts, pinned:
/// presence is honest, names are the sender's own, and the header's three
/// states carry the right words in the right colour.
void main() {
  final now = DateTime(2026, 11, 14, 12);

  group('presence', () {
    test('nobody is online without a heartbeat', () {
      expect(Presence.unknown.isOnlineAt(now), isFalse);
      expect(Presence.unknown.isKnown, isFalse);
      expect(Presence.unknown.label(now), 'offline');
      expect(now.isAfter(now), isFalse);
    });

    test('online is a 90 s window around the last heartbeat', () {
      expect(
        Presence(lastSeenAt: now.subtract(const Duration(seconds: 89)))
            .isOnlineAt(now),
        isTrue,
      );
      expect(
        Presence(lastSeenAt: now.subtract(const Duration(seconds: 91)))
            .isOnlineAt(now),
        isFalse,
      );
      // A clock that is a few seconds ahead must not flip the dot off.
      expect(
        Presence(lastSeenAt: now.add(const Duration(seconds: 3)))
            .isOnlineAt(now),
        isTrue,
      );
    });

    test('the label is online, else how long ago — never a guessed status', () {
      String label(Duration ago) =>
          Presence(lastSeenAt: now.subtract(ago)).label(now);

      expect(label(Duration.zero), 'online');
      expect(label(const Duration(seconds: 90)), 'last seen 1m ago');
      expect(label(const Duration(minutes: 5)), 'last seen 5m ago');
      expect(label(const Duration(hours: 3)), 'last seen 3h ago');
      expect(label(const Duration(days: 1)), 'last seen yesterday');
      expect(label(const Duration(days: 4)), 'last seen 4d ago');
      expect(label(const Duration(days: 15)), 'last seen 2 weeks ago');
      expect(label(const Duration(days: 400)), 'last seen 1 year ago');
    });
  });

  group('media labels', () {
    Message message({
      MessageKind kind = MessageKind.file,
      String? name,
      int? bytes,
      int? durationMs,
    }) => Message(
      id: 'm1',
      conversationId: 'c1',
      senderId: 'u1',
      kind: kind,
      createdAt: now,
      mediaUrl: 'https://res.cloudinary.com/demo/image/upload/v1/x8fQ2z1a.jpg',
      mediaName: name,
      mediaBytes: bytes,
      durationMs: durationMs,
    );

    test('the sender\'s own file name wins over anything else', () {
      expect(
        MediaLabels.name(message(name: 'holiday-in-coxs-bazar.jpg')),
        'holiday-in-coxs-bazar.jpg',
      );
    });

    test(
      'a row without a stored name falls back to a human label, not a URL',
      () {
        final photo = MediaLabels.name(message(kind: MessageKind.image));
        expect(photo, 'Photo');
        expect(photo.contains('cloudinary'), isFalse);
        expect(
          MediaLabels.name(message(kind: MessageKind.audio)),
          'Voice note',
        );
        expect(MediaLabels.name(message(name: '   ')), 'File');
      },
    );

    test('byline reads sender → recipient in both directions', () {
      // Mahmoud is looking at the thread: Saiful's photo reads Saiful → Mahmoud…
      expect(
        MediaLabels.byline(mine: false, myName: 'Mahmoud', peerName: 'Saiful'),
        'Saiful → Mahmoud',
      );
      // …and Mahmoud's own photo reads Mahmoud → Saiful.
      expect(
        MediaLabels.byline(mine: true, myName: 'Mahmoud', peerName: 'Saiful'),
        'Mahmoud → Saiful',
      );
      expect(
        MediaLabels.byline(mine: false, myName: 'Mo', peerName: null),
        isNull,
      );
    });

    test('badge and duration are derived, never invented', () {
      expect(MediaLabels.extensionBadge('contract.pdf'), 'PDF');
      expect(MediaLabels.extensionBadge('no-extension'), 'FILE');
      expect(MediaLabels.extensionBadge('clip.mpeg4'), 'MPEG');
      expect(MediaLabels.duration(message(durationMs: 42000)), '0:42');
      expect(MediaLabels.duration(message()), isNull);
      expect(MediaLabels.duration(message(durationMs: 0)), isNull);
    });

    test('size formatting is shared with the picker', () {
      expect(MediaLabels.meta(message(bytes: 0)), isNull);
      expect(MediaLabels.meta(message(bytes: 12 * 1024 * 1024)), '12.0 MB');
    });
  });

  group('header status', () {
    final conversation = Conversation(
      id: 'c1',
      peer: const ChatPeer(id: 'u2', displayName: 'Saiful', username: 'saiful'),
      myRole: GroupRole.owner,
    );

    Future<Color?> pumpStatus(
      WidgetTester tester, {
      required Presence presence,
      required String shown,
      bool typing = false,
      bool offline = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InboxHeader(
              conversation: conversation,
              compact: false,
              peerTyping: typing,
              offline: offline,
              presence: presence,
              now: now,
              onBack: () {},
              onCall: null,
              onVideoCall: null,
              onInfo: null,
              onProfile: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final text = tester.widget<Text>(find.text(shown));
      return text.style?.color;
    }

    testWidgets('online is the word "online", exactly', (tester) async {
      final color = await pumpStatus(
        tester,
        presence: Presence(
          lastSeenAt: now.subtract(const Duration(seconds: 10)),
        ),
        shown: 'online',
      );
      expect(find.text('online'), findsOneWidget);
      expect(color, AppColors.online);
    });

    testWidgets('away reads as last seen in the muted colour', (tester) async {
      final color = await pumpStatus(
        tester,
        presence: Presence(
          lastSeenAt: now.subtract(const Duration(minutes: 5)),
        ),
        shown: 'last seen 5m ago',
      );
      expect(find.text('last seen 5m ago'), findsOneWidget);
      expect(color, isNot(AppColors.online));
    });

    testWidgets('typing outranks presence, offline outranks presence', (
      tester,
    ) async {
      final typingColor = await pumpStatus(
        tester,
        presence: Presence.unknown,
        shown: 'typing',
        typing: true,
      );
      expect(find.text('typing'), findsOneWidget);
      expect(typingColor, isNot(AppColors.online));

      await pumpStatus(
        tester,
        presence: Presence.unknown,
        shown: 'offline — showing saved messages',
        offline: true,
      );
      expect(find.text('offline — showing saved messages'), findsOneWidget);
    });
  });
}
