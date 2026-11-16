@Tags(['qa'])
// Frame-by-frame look at the inbox row motion.
//
// Not an assertion suite — it renders the real widgets at chosen moments and
// writes PNGs next to this file so the motion can be inspected by eye:
//
//   flutter test test/qa/preview_frames_test.dart --run-skipped --update-goldens
//
// (Skipped during a normal `flutter test` run; see dart_test.yaml.)
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/core/motion/pulse_motion.dart';
import 'package:pulse/core/theme/app_colors.dart';
import 'package:pulse/core/theme/app_spacing.dart';
import 'package:pulse/core/theme/app_typography.dart';
import 'package:pulse/features/chat/domain/conversation.dart';
import 'package:pulse/features/chat/presentation/chats_screen.dart';
import 'package:pulse/features/chat/presentation/widgets/pulse_list_motion.dart';

final GlobalKey _rootKey = GlobalKey();

const _sdkFonts =
    '/home/user/.cache/tools/flutter/bin/cache/artifacts/material_fonts';

/// Register the app's own faces plus the two the platform would supply, so the
/// frames show real glyphs instead of the test font's boxes.
Future<void> _loadFonts() async {
  final poppins = FontLoader('Poppins');
  for (final f in [
    'Poppins-Regular.ttf',
    'Poppins-Medium.ttf',
    'Poppins-SemiBold.ttf',
    'Poppins-Bold.ttf',
  ]) {
    poppins.addFont(rootBundle.load('assets/fonts/$f'));
  }
  await poppins.load();

  final roboto = FontLoader('Roboto');
  for (final f in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    roboto.addFont(
      Future.value(
        ByteData.sublistView(File('$_sdkFonts/$f').readAsBytesSync()),
      ),
    );
  }
  await roboto.load();

  final icons = FontLoader('MaterialIcons');
  icons.addFont(
    Future.value(
      ByteData.sublistView(
        File('$_sdkFonts/MaterialIcons-Regular.otf').readAsBytesSync(),
      ),
    ),
  );
  await icons.load();
}

final _now = DateTime.now();

final _extra = <List<String>>[
  ['Shakil Ahmed', 'Done, thanks', '4 d'],
  ['Rehnuma Tabassum', 'Let me check and get back', '5 d'],
  ['Arif Mahmud', 'Received', '6 d'],
  ['Tahmina Begum', 'Happy birthday!', '1 w'],
  ['Jubayer Alam', 'Meeting moved to 4', '1 w'],
  ['Sumaiya Rahman', 'Sent on mail', '2 w'],
];

final _items = <Conversation>[
  Conversation(
    id: 'c0',
    peer: const ChatPeer(id: 'p0', displayName: 'Ayesha Karim'),
    lastMessagePreview: 'Sent the revised deck, have a look',
    lastMessageSenderId: 'p0',
    lastMessageAt: _now.subtract(const Duration(minutes: 2)),
    unreadCount: 3,
  ),
  Conversation(
    id: 'c1',
    peer: const ChatPeer(id: 'p1', displayName: 'Rifat Hossain'),
    lastMessagePreview: 'Call me when you are free',
    lastMessageSenderId: 'me',
    lastMessageAt: _now.subtract(const Duration(minutes: 18)),
  ),
  Conversation(
    id: 'c2',
    peer: const ChatPeer(id: 'p2', displayName: 'Nusrat Jahan'),
    lastMessagePreview: 'ok',
    lastMessageSenderId: 'p2',
    lastMessageAt: _now.subtract(const Duration(minutes: 41)),
    unreadCount: 128,
  ),
  Conversation(
    id: 'c3',
    peer: const ChatPeer(id: 'p3', displayName: 'Tanvir Ahmed'),
    lastMessagePreview: 'The invoice is attached',
    lastMessageSenderId: 'me',
    lastMessageAt: _now.subtract(const Duration(hours: 1)),
  ),
  Conversation(
    id: 'c4',
    peer: const ChatPeer(id: 'p4', displayName: 'Sadia Islam'),
    lastMessagePreview: 'See you at 6 then',
    lastMessageAt: _now.subtract(const Duration(hours: 3)),
  ),
  Conversation(
    id: 'c5',
    kind: 'group',
    peer: const ChatPeer(id: 'g5', displayName: 'Design Team'),
    title: 'Design Team',
    memberCount: 12,
    lastMessagePreview: 'Rifat: pushed the new screens',
    lastMessageSenderId: 'p1',
    lastMessageAt: _now.subtract(const Duration(hours: 5)),
    unreadCount: 2,
  ),
  Conversation(
    id: 'c6',
    peer: const ChatPeer(id: 'p6', displayName: 'Farhana Akter'),
    lastMessagePreview: 'Could you resend the link?',
    lastMessageAt: _now.subtract(const Duration(days: 1)),
  ),
  Conversation(
    id: 'c7',
    peer: const ChatPeer(id: 'p7', displayName: 'Mahmudul Hasan'),
    lastMessagePreview: 'Perfect, that works',
    lastMessageAt: _now.subtract(const Duration(days: 3)),
  ),
  for (var i = 0; i < _extra.length; i++)
    Conversation(
      id: 'x$i',
      peer: ChatPeer(id: 'xp$i', displayName: _extra[i][0]),
      lastMessagePreview: _extra[i][1],
      lastMessageSenderId: i.isEven ? 'me' : 'xp$i',
      lastMessageAt: _now.subtract(Duration(days: 4 + i)),
    ),
];

Widget _screen() => RepaintBoundary(
  key: _rootKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: AppColors.bg,
    ),
    home: Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenX,
                18,
                AppSpacing.screenX,
                12,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Messages',
                  style: AppTypography.displaySmall.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PulseEdgeFade(
                child: CustomScrollView(
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverList.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: PulseMotion.rowGap),
                      itemBuilder: (context, i) => Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.screenX,
                          i == 0 ? PulseMotion.featherTop : 0,
                          AppSpacing.screenX,
                          0,
                        ),
                        child: ConversationTile(
                          conversation: _items[i],
                          myId: 'me',
                          index: i,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 140)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _shot(String name) =>
    expectLater(find.byKey(_rootKey), matchesGoldenFile('frames/$name.png'));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  testWidgets('inbox row motion, frame by frame', (tester) async {
    tester.view.physicalSize = const Size(860, 1864); // 430 × 932 @2x
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_screen());
    await tester.pump(); // first frame

    await tester.pump(const Duration(milliseconds: 140));
    await _shot('01-enter-140ms');

    await tester.pump(const Duration(milliseconds: 160)); // ≈300 ms in
    await _shot('02-enter-300ms');

    await tester.pump(const Duration(milliseconds: 900)); // settled
    await _shot('03-settled');

    // Press and hold on a row that is on screen: sink + water burst.
    final row = find.byType(ConversationTile).at(2);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 70));
    await _shot('04-press-70ms');
    await tester.pump(const Duration(milliseconds: 260));
    await _shot('05-press-330ms');
    await tester.pump(const Duration(milliseconds: 300));
    await _shot('06-press-630ms');
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 90));
    await _shot('07-release-90ms');

    // Scroll so rows run past both edges (scroll-depth treatment).
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
    await tester.pump(const Duration(milliseconds: 16));
    await _shot('08-scrolled-180');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pump(const Duration(milliseconds: 16));
    await _shot('09-scrolled-600');

    await tester.pumpAndSettle();
    await _shot('10-settled');
  });
}
