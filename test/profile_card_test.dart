import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/profile/domain/profile.dart';
import 'package:pulse/features/profile/domain/profile_privacy.dart';
import 'package:pulse/features/profile/domain/profile_time.dart';
import 'package:pulse/features/profile/domain/profile_view_mode.dart';
import 'package:pulse/features/profile/domain/right_now.dart';
import 'package:pulse/features/profile/presentation/widgets/right_now_grid.dart';
import 'package:pulse/features/profile/presentation/widgets/settings_lens.dart';

/// The card's promises, as tests.
///
/// The design is unusual in one way: every value on "Right now" has to be
/// attributable. So the tests are less about pixels and more about **what the
/// card refuses to show** — no place unless it was typed, no time unless an
/// offset exists, no listening row ever.
void main() {
  const profile = Profile(
    id: 'u1',
    displayName: 'Saiful Islam',
    username: 'saiful',
    bio: 'Quiet software, loud playlists.',
    statusText: 'Building Pulse, every night',
    whereText: 'Chattogram, BD',
    timezone: 'Dhaka',
    utcOffsetMinutes: 360,
    joinedAt: null,
    labels: <String>['Family', 'Cricket'],
  );

  final joined = DateTime.utc(2024, 3, 18, 12);
  final full = profile.copyWith();

  group('Right now', () {
    test('carries the four stored values, in card order', () {
      final board = RightNowBoard.of(
        profile: Profile(
          id: 'u1',
          displayName: 'Saiful Islam',
          username: 'saiful',
          statusText: 'Building Pulse, every night',
          whereText: 'Chattogram, BD',
          timezone: 'Dhaka',
          utcOffsetMinutes: 360,
          joinedAt: joined,
        ),
        now: DateTime.utc(2026, 11, 14, 12, 11),
      );

      expect(board.entries.map((e) => e.kind), <RightNowKind>[
        RightNowKind.status,
        RightNowKind.localTime,
        RightNowKind.where,
        RightNowKind.joined,
      ]);
      expect(board.entries.last.value, 'March 2024');
    });

    test('local time is arithmetic on the stored offset', () {
      final board = RightNowBoard.of(
        profile: full,
        // 12:11 UTC + 06:00 = 6:11 PM in Dhaka.
        now: DateTime.utc(2026, 11, 14, 12, 11),
      );
      final time = board.entries.firstWhere(
        (e) => e.kind == RightNowKind.localTime,
      );
      expect(time.value, '6:11 PM · Dhaka');
    });

    test('an empty place hides the row instead of inventing one', () {
      final board = RightNowBoard.of(
        profile: full.copyWith(whereText: '   '),
        now: DateTime.utc(2026, 11, 14, 12),
      );
      expect(
        board.entries.any((e) => e.kind == RightNowKind.where),
        isFalse,
      );
    });

    test('an empty status hides its tile too', () {
      final board = RightNowBoard.of(
        profile: full.copyWith(statusText: ''),
        now: DateTime.utc(2026, 11, 14, 12),
      );
      expect(board.entries.any((e) => e.kind == RightNowKind.status), isFalse);
      // The clock is always available, so the grid is never empty.
      expect(board.isEmpty, isFalse);
    });

    test('there is no listening row, because it cannot be known', () {
      final board = RightNowBoard.of(profile: full, now: DateTime.utc(2026));
      final labels = board.entries.map((e) => e.label.toLowerCase()).toList();
      expect(labels.any((l) => l.contains('listening')), isFalse);
      expect(labels.any((l) => l.contains('playing')), isFalse);
    });

    test('a visitor is told "theirs", the owner is told "yours"', () {
      final board = RightNowBoard.of(profile: full, now: DateTime.utc(2026));
      final where = board.entries.firstWhere(
        (e) => e.kind == RightNowKind.where,
      );
      expect(where.sourceFor(ProfileViewMode.owner), contains('You typed'));
      expect(where.sourceFor(ProfileViewMode.visitor), contains('Typed by them'));
    });
  });

  group('the clock on the card', () {
    test('renders in the profile zone, not the reader zone', () {
      const time = ProfileTime(offsetMinutes: -300, label: 'New York');
      expect(time.displayAt(DateTime.utc(2026, 11, 14, 23, 30)), '6:30 PM · New York');
      expect(time.offsetLabel, 'UTC-05:00');
    });

    test('midnight is 12 AM and noon is 12 PM', () {
      const time = ProfileTime(offsetMinutes: 0);
      expect(time.clockAt(DateTime.utc(2026, 1, 1, 0, 5)), '12:05 AM');
      expect(time.clockAt(DateTime.utc(2026, 1, 1, 12, 0)), '12:00 PM');
    });

    test('no stored offset falls back to the device zone', () {
      final fallback = ProfileTime.fromLocalDevice(DateTime(2026, 1, 1));
      expect(fallback.offsetMinutes, isA<int>());
    });
  });

  group('privacy', () {
    test('one switch writes exactly one column', () {
      const privacy = ProfilePrivacy.defaults;
      final off = privacy.withValue(PrivacyField.readReceipts, true);
      expect(off.readReceipts, isTrue);
      expect(off.toColumnMap(PrivacyField.readReceipts), {
        'read_receipts': true,
      });
      // Nothing else moved.
      expect(off.lastSeenVisible, privacy.lastSeenVisible);
      expect(off.chatLock, privacy.chatLock);
    });

    test('defaults match the column defaults in 0012', () {
      const privacy = ProfilePrivacy.defaults;
      expect(privacy.lastSeenVisible, isTrue);
      expect(privacy.readReceipts, isFalse);
      expect(privacy.photoVisible, isTrue);
      expect(privacy.notifications, isTrue);
      expect(privacy.chatLock, isFalse);
    });
  });

  group('the row shape', () {
    test('new columns parse, and a missing row reads as empty', () {
      final parsed = Profile.fromMap(<String, dynamic>{
        'id': 'u1',
        'display_name': 'Saiful Islam',
        'username': 'saiful',
        'status_text': 'Building Pulse',
        'where_text': 'Chattogram, BD',
        'timezone': 'Dhaka',
        'utc_offset_minutes': 360,
        'labels': <String>['Family', 'Work', ''],
        'joined_at': '2024-03-18T00:00:00Z',
      });
      expect(parsed.statusText, 'Building Pulse');
      expect(parsed.whereText, 'Chattogram, BD');
      expect(parsed.utcOffsetMinutes, 360);
      expect(parsed.labels, <String>['Family', 'Work']);
      expect(parsed.handle, '@saiful');
      expect(parsed.shareLink, 'pulse.app/@saiful');
      expect(parsed.privacy.readReceipts, isFalse);
    });

    test('the field limits match the CHECK constraints', () {
      expect(Profile.validateStatus('x' * 81), isNotNull);
      expect(Profile.validateStatus('x' * 80), isNull);
      expect(Profile.validateWhere('x' * 41), isNotNull);
      expect(Profile.validateLabel('x' * 21), isNotNull);
      expect(Profile.maxLabels, 6);
    });
  });

  group('the widget', () {
    testWidgets('says where every value came from', (tester) async {
      final board = RightNowBoard.of(profile: full, now: DateTime.utc(2026));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RightNowGrid(
                board: board,
                mode: ProfileViewMode.owner,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('You typed this · friends'), findsOneWidget);
      expect(find.text('From your timezone'), findsOneWidget);
      expect(find.text(RightNowBoard.disclaimer), findsOneWidget);
    });

    testWidgets('a visitor never sees the owner switches', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsLens(
                mode: ProfileViewMode.visitor,
                privacy: ProfilePrivacy.defaults,
                onToggle: (_, _) {},
                onSaveContact: () {},
                onDanger: (_, _, _) {},
                onConnection: () {},
                onAbout: () {},
                onLogout: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('THIS CHAT'), findsOneWidget);
      expect(find.text('WHO SEES WHAT'), findsNothing);
      expect(find.text('SECURITY'), findsNothing);
    });

    testWidgets('the owner sees them, and the danger block', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsLens(
                mode: ProfileViewMode.owner,
                privacy: ProfilePrivacy.defaults,
                onToggle: (_, _) {},
                onSaveContact: () {},
                onDanger: (_, _, _) {},
                onConnection: () {},
                onAbout: () {},
                onLogout: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('WHO SEES WHAT'), findsOneWidget);
      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.text('IF IT HAS TO END'), findsOneWidget);
      expect(find.text('THIS CHAT'), findsNothing);
    });
  });
}
