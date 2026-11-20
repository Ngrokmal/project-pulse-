@Tags(['qa'])
// The Blocked people page, rendered outside the app so its design can be
// inspected by eye — no Supabase, no session, just the real screen with real
// rows (an empty list, and a list with people in it).
//
//   flutter test test/qa/blocked_frames_test.dart --run-skipped --update-goldens
//
// Skipped during a normal `flutter test` run (see dart_test.yaml).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/profile/application/profile_controller.dart';
import 'package:pulse/features/profile/domain/blocked_person.dart';
import 'package:pulse/features/profile/presentation/blocked_people_screen.dart';

import '../support/fake_profile_repository.dart';

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

final List<BlockedPerson> _rows = <BlockedPerson>[
  BlockedPerson(
    id: 'u1',
    displayName: 'Rifat Hossain',
    username: '@rifat',
    blockedAt: DateTime.now().subtract(const Duration(minutes: 12)),
  ),
  BlockedPerson(
    id: 'u2',
    displayName: 'Tania Rahman',
    username: '@tania',
    blockedAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  BlockedPerson(
    id: 'u3',
    displayName: 'A stranger',
    blockedAt: DateTime.now().subtract(const Duration(days: 61)),
  ),
];

Widget _harness(List<BlockedPerson> rows) {
  return RepaintBoundary(
    key: _rootKey,
    child: ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(blocked: rows),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Poppins'),
        home: const BlockedPeopleScreen(),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('blocked people, with a list', (tester) async {
    phone(tester);
    await tester.pumpWidget(_harness(_rows));
    // Resolve the provider off the fake's future, then land the switcher.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/blocked-list.png'),
    );
  });

  testWidgets('blocked people, nobody blocked', (tester) async {
    phone(tester);
    await tester.pumpWidget(_harness(const <BlockedPerson>[]));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await expectLater(
      find.byKey(_rootKey),
      matchesGoldenFile('frames/blocked-empty.png'),
    );
  });
}
