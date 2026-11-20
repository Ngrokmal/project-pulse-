@Tags(['qa'])
// The Profile card, rendered outside the app so its layout can be inspected by
// eye — no Supabase, no session, just the real widgets with real values.
//
//   flutter test test/qa/profile_card_frames_test.dart --run-skipped --update-goldens
//
// Skipped during a normal `flutter test` run (see dart_test.yaml).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/core/theme/app_colors.dart';
import 'package:pulse/features/profile/domain/profile.dart';
import 'package:pulse/features/profile/domain/profile_media.dart';
import 'package:pulse/features/profile/domain/profile_privacy.dart';
import 'package:pulse/features/profile/domain/profile_view_mode.dart';
import 'package:pulse/features/profile/domain/right_now.dart';
import 'package:pulse/features/profile/presentation/widgets/media_lens.dart';
import 'package:pulse/features/profile/presentation/widgets/people_lens.dart';
import 'package:pulse/features/profile/presentation/widgets/profile_app_bar.dart';
import 'package:pulse/features/profile/presentation/widgets/profile_footer.dart';
import 'package:pulse/features/profile/presentation/widgets/profile_hero.dart';
import 'package:pulse/features/profile/presentation/widgets/profile_identity_card.dart';
import 'package:pulse/features/profile/presentation/widgets/profile_lens_rail.dart';
import 'package:pulse/features/profile/application/profile_sync_controller.dart';
import 'package:pulse/features/profile/domain/account_session.dart';
import 'package:pulse/features/profile/presentation/widgets/safety_lens.dart';
import 'package:pulse/features/profile/presentation/widgets/settings_lens.dart';
import 'package:pulse/features/profile/presentation/widgets/story_lens.dart';
import 'package:pulse/features/profile/domain/profile_lens.dart';

final GlobalKey _rootKey = GlobalKey();

const _sdkFonts =
    '/home/user/.cache/tools/flutter/bin/cache/artifacts/material_fonts';

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

final Profile _profile = Profile(
  id: 'u1',
  displayName: 'Saiful Islam',
  username: 'saiful',
  bio:
      'I build quiet software and loud playlists. Fridays are for cricket, '
      'mornings are for filter coffee — and if I owe you a reply, it is coming.',
  statusText: 'Building Pulse, every night',
  whereText: 'Chattogram, BD',
  timezone: 'Dhaka',
  utcOffsetMinutes: 360,
  joinedAt: DateTime.utc(2024, 3, 18, 9),
  labels: const <String>['Family', 'Work', 'Cricket'],
);

final Profile _empty = const Profile(
  id: 'u2',
  displayName: 'Saiful Islam',
  username: 'saiful',
);

class _Preview extends StatelessWidget {
  const _Preview({
    required this.lens,
    required this.mode,
    required this.child,
    this.profile,
  });

  final ProfileLens lens;
  final ProfileViewMode mode;
  final Widget child;
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile ?? _profile;
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
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ProfileHero(
                      initials: p.initials,
                      avatarUrl: null,
                      isVisitor: mode.isVisitor,
                      onTapAvatar: () {},
                    ),
                    Transform.translate(
                      offset: const Offset(0, -52),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: ProfileIdentityCard(
                              profile: p,
                              mode: mode,
                              onAction: (_) {},
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ProfileLensRail(
                                  lens: lens,
                                  mode: mode,
                                  onSelect: (_) {},
                                ),
                                const SizedBox(height: 18),
                                child,
                                const SizedBox(height: 22),
                                const ProfileFooter(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ProfileAppBar(
                  scrolled: false,
                  mode: mode,
                  onBack: () {},
                  onMode: (_) {},
                  onCode: () {},
                  onMore: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _story(ProfileViewMode mode, {Profile? profile}) {
  final p = profile ?? _profile;
  return StoryLens(
    profile: p,
    mode: mode,
    board: RightNowBoard.of(
      profile: p,
      now: DateTime.utc(2026, 11, 14, 12, 11),
    ),
    maskedEmail: 'sa••••@gmail.com',
    onTileTap: (_) {},
    onCopyHandle: () {},
    onCopyLink: () {},
    onAddLabel: () {},
    onRemoveLabel: (_) {},
  );
}

void main() {
  setUpAll(_loadFonts);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('story, owner', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: _Preview(
          lens: ProfileLens.story,
          mode: ProfileViewMode.owner,
          child: _story(ProfileViewMode.owner),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/story-owner.png'),
    );
  });

  testWidgets('story, visitor', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: _Preview(
          lens: ProfileLens.story,
          mode: ProfileViewMode.visitor,
          child: _story(ProfileViewMode.visitor),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/story-visitor.png'),
    );
  });

  testWidgets('story, a brand-new card with nothing typed yet', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: _Preview(
          lens: ProfileLens.story,
          mode: ProfileViewMode.owner,
          profile: _empty,
          child: _story(ProfileViewMode.owner, profile: _empty),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/story-empty.png'),
    );
  });

  testWidgets('people', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: _Preview(
          lens: ProfileLens.people,
          mode: ProfileViewMode.owner,
          child: PeopleLens(
            faces: const [
              PeopleFace(initials: 'MA', tone: 0),
              PeopleFace(initials: 'AB', tone: 1),
              PeopleFace(initials: 'OK', tone: 2),
              PeopleFace(initials: 'LO', tone: 3),
            ],
            circles: const [
              PeopleCircle(
                title: 'Weekend Cricket',
                subtitle: '9 people in this one',
                initials: 'WC',
              ),
              PeopleCircle(
                title: 'Office · Design',
                subtitle: '4 people in this one',
                initials: 'OD',
              ),
              PeopleCircle(
                title: 'Family',
                subtitle: '6 people in this one',
                initials: 'FA',
              ),
            ],
            mode: ProfileViewMode.owner,
            knownLine: 'Mahmud, Abdullah, Oishi and others',
            onOpenCode: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/people.png'),
    );
  });

  testWidgets('media, nothing sent yet', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: _Preview(
          lens: ProfileLens.media,
          mode: ProfileViewMode.owner,
          child: MediaLens(
            state: const AsyncData(<ProfileMedia>[]),
            onRetry: () {},
            onOpen: (_) {},
            onOpenGallery: () {},
            onKeepOriginals: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/media-empty.png'),
    );
  });

  testWidgets('settings, owner', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: _Preview(
          lens: ProfileLens.settings,
          mode: ProfileViewMode.owner,
          child: PrivacyLens(
            privacy: ProfilePrivacy.defaults,
            sync: const ProfileSyncState(),
            onToggle: (_, _) {},
            onRetrySync: () {},
            sessions: const AsyncValue.data(<AccountSession>[]),
            sessionsNow: DateTime(2026, 11, 14),
            onSignOutOthers: () async {},
            onBlockedPeople: () {},
            onConnection: () {},
            onAbout: () {},
            onLogout: () {},
            maskedEmail: 'ri••••@pulse.chat',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/settings-owner.png'),
    );
  });

  testWidgets('safety, visitor', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        child: _Preview(
          lens: ProfileLens.settings,
          mode: ProfileViewMode.visitor,
          child: SafetyLens(
            givenName: 'Rifat',
            preview: true,
            blocked: false,
            notifications: true,
            onNotifications: (_) {},
            onSaveContact: () {},
            onAction: (_) {},
            onReport: () {},
            onUnblock: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/safety-visitor.png'),
    );
  });
}
