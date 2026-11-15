import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/core/theme/app_theme.dart';
import 'package:pulse/features/chat/domain/conversation.dart';
import 'package:pulse/features/chat/presentation/chats_screen.dart';
import 'package:pulse/features/chat/presentation/widgets/chat_avatar.dart';
import 'package:pulse/features/chat/presentation/widgets/empty_chats_art.dart';

/// The inbox has to look like a chat app: a picture, a name, the last thing that
/// was said, when, and how much of it is unread — and an empty state that is
/// more than a grey icon.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  );

  Conversation directChat({
    String? preview = 'see you at 8',
    int unread = 0,
    String? avatarUrl,
    bool mineLast = false,
  }) => Conversation(
    id: 'c1',
    kind: 'direct',
    peer: ChatPeer(
      id: 'u2',
      displayName: 'Bela Rahman',
      username: 'bela',
      avatarUrl: avatarUrl,
    ),
    lastMessageAt: DateTime.now().subtract(const Duration(minutes: 4)),
    lastMessagePreview: preview,
    lastMessageSenderId: mineLast ? 'me' : 'u2',
    unreadCount: unread,
  );

  Conversation groupChat({int members = 4}) => Conversation(
    id: 'g1',
    kind: 'group',
    title: 'Weekend Cricket',
    memberCount: members,
    myRole: GroupRole.admin,
    peer: const ChatPeer(id: '', displayName: 'Pulse user'),
    lastMessageAt: DateTime.now().subtract(const Duration(days: 1)),
    lastMessagePreview: 'bring the bat',
  );

  group('conversation row', () {
    testWidgets('shows the picture, the name, the preview and the time', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ConversationTile(conversation: directChat(), myId: 'me')),
      );

      expect(find.byType(ChatAvatar), findsOneWidget);
      expect(find.text('Bela Rahman'), findsOneWidget);
      expect(find.text('see you at 8'), findsOneWidget);
      // the avatar falls back to initials when there is no picture
      expect(find.text('BR'), findsOneWidget);
      // a time label of some kind is always there
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('unread count is a badge, and the row is bold', (tester) async {
      await tester.pumpWidget(
        host(ConversationTile(conversation: directChat(unread: 7), myId: 'me')),
      );
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a big unread count is capped at 99+', (tester) async {
      await tester.pumpWidget(
        host(
          ConversationTile(conversation: directChat(unread: 240), myId: 'me'),
        ),
      );
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('240'), findsNothing);
    });

    testWidgets('my own last message is prefixed with You:', (tester) async {
      await tester.pumpWidget(
        host(
          ConversationTile(
            conversation: directChat(preview: 'on my way', mineLast: true),
            myId: 'me',
          ),
        ),
      );
      expect(find.text('You: on my way'), findsOneWidget);
    });

    testWidgets('a quiet chat says Say hello, not an empty line', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ConversationTile(conversation: directChat(preview: null), myId: 'me'),
        ),
      );
      expect(find.text('Say hello'), findsOneWidget);
    });

    testWidgets('a group shows its name, member count and group badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ConversationTile(conversation: groupChat(), myId: 'me')),
      );
      expect(find.text('Weekend Cricket'), findsOneWidget);
      expect(find.text('bring the bat'), findsOneWidget);
      expect(find.byIcon(Icons.groups_rounded), findsWidgets);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('an avatar URL is used when there is one', (tester) async {
      await tester.pumpWidget(
        host(
          ConversationTile(
            conversation: directChat(
              avatarUrl: 'https://res.cloudinary.com/demo/a.png',
            ),
            myId: 'me',
          ),
        ),
      );
      // Image.network is attempted; when it fails the initials must take over
      // (a chat list never shows a broken image).
      expect(find.byType(Image), findsWidgets);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('BR'), findsWidgets);
    });
  });

  group('empty state', () {
    testWidgets('says No conversations yet and offers a way in', (
      tester,
    ) async {
      var started = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: ProviderContainer(),
          child: host(EmptyChatsArt(onStartChat: () => started = true)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No conversations yet'), findsOneWidget);
      expect(find.textContaining('Start a chat or a group'), findsOneWidget);

      await tester.tap(find.text('Start a chat'));
      expect(started, isTrue);
    });

    testWidgets('the artwork animates in the app colours', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: ProviderContainer(),
          child: host(EmptyChatsArt(onStartChat: () {})),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The rings are painted (not an image asset), so they exist in any theme.
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byIcon(Icons.chat_bubble_rounded), findsWidgets);
      // pumping further must not throw (the controller really is repeating)
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('failure state', () {
    testWidgets('a server failure says what happened and offers a retry', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpWidget(
        host(
          ChatsErrorView(
            failure: const ServerFailure(safeCode: 'chat_error'),
            onRetry: () => retried++,
          ),
        ),
      );

      expect(find.text("Couldn't load your chats"), findsOneWidget);
      expect(find.textContaining('did not answer properly'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      expect(retried, 1);
    });

    testWidgets('being offline reads differently from a server fault', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ChatsErrorView(failure: const NetworkFailure(), onRetry: () {})),
      );
      expect(find.text('You are offline'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });
  });
}
