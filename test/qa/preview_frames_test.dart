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
import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/core/motion/pulse_motion.dart';
import 'package:pulse/core/theme/app_colors.dart';
import 'package:pulse/core/theme/app_spacing.dart';
import 'package:pulse/features/chat/domain/conversation.dart';
import 'package:pulse/core/motion/pulse_icons.dart';
import 'package:pulse/features/chat/presentation/chats_screen.dart';
import 'package:pulse/features/chat/presentation/widgets/pulse_notification_sheet.dart';
import 'package:pulse/features/chat/presentation/widgets/pulse_search_field.dart';
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

final GlobalKey<_HarnessState> _harness = GlobalKey<_HarnessState>();
_HarnessState get _harnessState => _harness.currentState!;

/// Just enough of the screen to look at: the real chrome widgets, driven the
/// way the app drives them, with stand-in conversations.
class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SingleTickerProviderStateMixin {
  late final AnimationController _search = AnimationController(
    vsync: this,
    duration: PulseMotion.searchOpen,
  );
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  String _needle = '';
  bool _sheet = false;

  @override
  void dispose() {
    _search.dispose();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void openSearch() {
    _search.forward();
  }

  void type(String q) => setState(() {
    _needle = q;
    _query.text = q;
  });

  void openSheet() => setState(() => _sheet = true);

  @override
  Widget build(BuildContext context) {
    final typing = _needle.trim().isNotEmpty;
    final matched = <Conversation>[];
    final rest = <Conversation>[];
    for (final c in _items) {
      final hay = '${c.displayName} ${c.lastMessagePreview ?? ''}'
          .toLowerCase();
      (hay.contains(_needle.trim().toLowerCase()) ? matched : rest).add(c);
    }
    final ordered = typing ? <Conversation>[...matched, ...rest] : _items;
    final hits = matched.map((c) => c.id).toSet();
    final hero = typing && matched.isNotEmpty ? matched.first.id : null;

    return RepaintBoundary(
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
            child: Stack(
              children: [
                Column(
                  children: [
                    PulseAppBar(
                      t: _search,
                      onSearch: openSearch,
                      onBell: openSheet,
                    ),
                    PulseSearchField(
                      t: _search,
                      controller: _query,
                      focusNode: _focus,
                      onChanged: type,
                      onClose: () {},
                    ),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _search,
                        builder: (context, child) {
                          final k = typing ? 0.0 : _search.value;
                          Widget v = child!;
                          if (k > 0.001) {
                            v = ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: 0.8 * k,
                                sigmaY: 0.8 * k,
                              ),
                              child: v,
                            );
                          }
                          return Opacity(
                            opacity: 1 - 0.58 * k,
                            child: Transform.scale(
                              scale: 1 - 0.018 * k,
                              child: v,
                            ),
                          );
                        },
                        child: PulseEdgeFade(
                          child: CustomScrollView(
                            physics: const ClampingScrollPhysics(),
                            slivers: [
                              SliverList.separated(
                                itemCount: ordered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: PulseMotion.rowGap),
                                itemBuilder: (context, i) {
                                  final c = ordered[i];
                                  return Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      AppSpacing.screenX,
                                      i == 0 ? PulseMotion.featherTop : 0,
                                      AppSpacing.screenX,
                                      0,
                                    ),
                                    child: ConversationTile(
                                      key: ValueKey<String>(c.id),
                                      conversation: c,
                                      myId: 'me',
                                      index: i,
                                      dimmed: typing && !hits.contains(c.id),
                                      highlighted: typing && c.id == hero,
                                    ),
                                  );
                                },
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 140),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                PulseNotificationSheet(
                  open: _sheet,
                  notices: _notices,
                  onClose: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Harness-only copy — the app itself ships an empty list until a real
/// notification source exists.
const _notices = <PulseNoticeData>[
  PulseNoticeData(
    title: 'Scheduled maintenance',
    body: 'Tonight 2:00–2:20 AM. Chats stay saved.',
    when: '2m',
    icon: PulseIcons.warning,
    danger: true,
  ),
  PulseNoticeData(
    title: 'Alert delivered',
    body: 'Your force-audio alert reached every device.',
    when: '1h',
    icon: PulseIcons.shieldCheck,
  ),
  PulseNoticeData(
    title: 'New member',
    body: 'Someone joined one of your groups.',
    when: '3h',
    icon: PulseIcons.peopleAdd,
  ),
  PulseNoticeData(
    title: 'Alert played',
    body: 'A 42-second alert finished playing.',
    when: '4h',
    icon: PulseIcons.clock,
  ),
];

Future<void> _shot(String name) =>
    expectLater(find.byKey(_rootKey), matchesGoldenFile('frames/$name.png'));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  testWidgets('inbox row motion, frame by frame', (tester) async {
    tester.view.physicalSize = const Size(860, 1864); // 430 x 932 @2x
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_Harness(key: _harness));
    await tester.pump();
    await tester.pump(
      const Duration(milliseconds: 900),
    ); // entrance done, logo running
    await _shot('01-rest');

    await tester.pump(const Duration(milliseconds: 140));
    await _shot('02-logo-beat');

    // press and hold on a row: sink + water burst
    final row = find.byType(ConversationTile).at(2);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 70));
    await _shot('03-press-70ms');
    await tester.pump(const Duration(milliseconds: 260));
    await _shot('04-press-330ms');
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 400));

    // search opening: the bar folds away while the field springs in
    _harnessState.openSearch();
    await tester.pump(const Duration(milliseconds: 160));
    await _shot('05-search-160ms');
    await tester.pump(const Duration(milliseconds: 200));
    await _shot('06-search-360ms');
    await tester.pump(const Duration(milliseconds: 400));
    await _shot('07-search-open');

    _harnessState.type('ri');
    await tester.pump(const Duration(milliseconds: 400));
    await _shot('08-search-query');

    _harnessState.type('');
    await tester.pump(const Duration(milliseconds: 300));

    // notifications sheet: staggered arrival
    _harnessState.openSheet();
    await tester.pump(const Duration(milliseconds: 180));
    await _shot('09-sheet-180ms');
    await tester.pump(const Duration(milliseconds: 300));
    await _shot('10-sheet-480ms');
    await tester.pump(const Duration(milliseconds: 700));
    await _shot('11-sheet-open');
  });
}
