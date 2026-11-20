import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/profile/application/profile_controller.dart';
import 'package:pulse/features/profile/application/profile_visits_controller.dart';
import 'package:pulse/features/profile/domain/profile.dart';
import 'package:pulse/features/profile/domain/profile_visitor.dart';

import 'support/fake_profile_repository.dart';

/// Profile views (0015), as the three promises the page makes:
///
/// 1. the list is the server's answer, not a local guess — a refresh re-asks it;
/// 2. a failure shows as a failure, never as "nobody has visited you";
/// 3. opening a card records exactly one visit and still opens when the write is
///    refused.
///
/// The server side of the same promise is
/// `supabase/tests/22_live_profile_visits_test.sql`, run against the real
/// project.
/// Riverpod 3 wraps a provider's failure on the way out; the failure the UI
/// shows is the one underneath.
Object? rootError(Object? error) =>
    error is ProviderException ? error.exception : error;

void main() {
  final now = DateTime(2026, 11, 20, 12);

  ProfileVisitor visitor({
    String id = 'v1',
    String name = 'Rifat Hossain',
    String? handle = 'rifat',
    int count = 1,
    Duration ago = const Duration(minutes: 12),
  }) => ProfileVisitor(
    id: id,
    displayName: name,
    username: handle,
    lastSeenAt: now.subtract(ago),
    visitCount: count,
  );

  group('the row says when, in words a person uses', () {
    test('minutes, hours, yesterday, days, weeks, months, a year', () {
      expect(visitor(ago: Duration.zero).visitedLabel(now), 'just now');
      expect(
        visitor(ago: const Duration(seconds: 40)).visitedLabel(now),
        'just now',
      );
      expect(
        visitor(ago: const Duration(minutes: 12)).visitedLabel(now),
        '12 min ago',
      );
      expect(
        visitor(ago: const Duration(hours: 5)).visitedLabel(now),
        '5 h ago',
      );
      expect(
        visitor(ago: const Duration(days: 1)).visitedLabel(now),
        'yesterday',
      );
      expect(
        visitor(ago: const Duration(days: 4)).visitedLabel(now),
        '4 days ago',
      );
      expect(
        visitor(ago: const Duration(days: 9)).visitedLabel(now),
        'last week',
      );
      expect(
        visitor(ago: const Duration(days: 21)).visitedLabel(now),
        '3 weeks ago',
      );
      expect(
        visitor(ago: const Duration(days: 90)).visitedLabel(now),
        '3 months ago',
      );
      expect(
        visitor(ago: const Duration(days: 400)).visitedLabel(now),
        'over a year ago',
      );
    });

    test('a clock that runs backwards never says "in 3 minutes"', () {
      expect(
        visitor(ago: const Duration(minutes: -5)).visitedLabel(now),
        'just now',
      );
    });

    test('the sentence counts the returns', () {
      expect(visitor(count: 1).describe(now), 'Visited 12 min ago');
      expect(visitor(count: 2).describe(now), 'Visited 12 min ago · twice');
      expect(visitor(count: 5).describe(now), 'Visited 12 min ago · 5 times');
    });

    test('initials are two letters, and a nameless row still has a face', () {
      expect(visitor(name: 'Rifat Hossain').initials, 'RH');
      expect(visitor(name: 'abdullah').initials, 'AB');
      expect(visitor(name: '   ').displayName, isNotEmpty);
    });

    test('the server row parses, and a missing timestamp is not "now"', () {
      final parsed = ProfileVisitor.fromMap(<String, dynamic>{
        'id': 'u9',
        'display_name': '  Tania Rahman ',
        'username': 'tania',
        'avatar_url': 'https://example.test/a.png',
        'last_seen_at': '2026-11-20T06:00:00Z',
        'visit_count': 3,
      });
      expect(parsed.displayName, 'Tania Rahman');
      expect(parsed.atHandle, '@tania');
      expect(parsed.visitCount, 3);
      expect(parsed.lastSeenAt.isUtc, isFalse);

      final blank = ProfileVisitor.fromMap(<String, dynamic>{'id': 'u9'});
      expect(blank.lastSeenAt.millisecondsSinceEpoch, 0);
      expect(blank.displayName, 'Pulse user');
    });
  });

  group('the list', () {
    ProviderContainer container(FakeProfileRepository repo) {
      final c = ProviderContainer(
        overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('comes from the server, and a refresh asks again', () async {
      final repo = FakeProfileRepository(visitors: [visitor()]);
      final c = container(repo);
      expect(await c.read(profileVisitorsProvider.future), hasLength(1));

      repo.visitors = [visitor(), visitor(id: 'v2', name: 'Tania Rahman')];
      await c.read(profileVisitorsProvider.notifier).refresh();
      expect(c.read(profileVisitorsProvider).value, hasLength(2));
    });

    test('a failure is a failure, not an empty page', () async {
      final repo = FakeProfileRepository(failVisitors: true);
      final c = container(repo);
      // Hold a listener so the provider is built and its failure is retained,
      // then let the failed future settle.
      final sub = c.listen(profileVisitorsProvider, (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      final state = c.read(profileVisitorsProvider);
      expect(state.hasError, isTrue);
      expect(rootError(state.error), isA<ServerFailure>());
    });
  });

  group('opening a card records the visit', () {
    final peer = Profile(
      id: 'peer-1',
      displayName: 'abdullah',
      username: 'abdullah',
    );

    ProviderContainer container(FakeProfileRepository repo) {
      final c = ProviderContainer(
        overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('one open, one visit', () async {
      final repo = FakeProfileRepository(peer: peer);
      final c = container(repo);
      final card = await c.read(peerCardProvider('peer-1').future);
      expect(card.id, 'peer-1');
      // The write is fired without awaiting; one turn of the loop settles it.
      await Future<void>.delayed(Duration.zero);
      expect(repo.recordedVisits, ['peer-1']);
    });

    test('the card still opens when the visit cannot be stored', () async {
      final repo = FakeProfileRepository(peer: peer, failVisit: true);
      final c = container(repo);
      final card = await c.read(peerCardProvider('peer-1').future);
      expect(card.displayName, 'abdullah');
    });

    test('a card that does not exist fails loudly', () async {
      final c = container(FakeProfileRepository());
      final request = peerCardProvider('missing');
      final sub = c.listen(request, (_, _) {});
      addTearDown(sub.close);
      await pumpEventQueue();

      expect(rootError(c.read(request).error), isA<ServerFailure>());
    });
  });
}
