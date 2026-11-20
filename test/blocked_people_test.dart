import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/profile/application/blocked_people_controller.dart';
import 'package:pulse/features/profile/application/profile_controller.dart';
import 'package:pulse/features/profile/domain/blocked_person.dart';

import 'support/fake_profile_repository.dart';

BlockedPerson _person({
  String id = 'u1',
  String name = 'Rifat Hossain',
  String? username = '@rifat',
  String? avatar,
  DateTime? at,
}) => BlockedPerson(
  id: id,
  displayName: name,
  username: username,
  avatarUrl: avatar,
  blockedAt: at ?? DateTime(2026, 11, 14, 9),
);

void main() {
  group('the row', () {
    test('parses what the function returns', () {
      final person = BlockedPerson.fromMap(<String, dynamic>{
        'id': 'u9',
        'display_name': '  Nusrat  ',
        'username': '@nusrat',
        'avatar_url': 'https://cdn.test/a.png',
        'blocked_at': '2026-11-13T10:00:00Z',
      });

      expect(person.id, 'u9');
      expect(person.displayName, 'Nusrat');
      expect(person.username, '@nusrat');
      expect(
        person.blockedLabel(DateTime(2026, 11, 14, 10)),
        'Blocked yesterday',
      );
    });

    test('a person with no name still gets a readable row', () {
      final person = BlockedPerson.fromMap(<String, dynamic>{
        'id': 'u1',
        'display_name': '   ',
        'blocked_at': '2026-11-14T09:59:00Z',
      });
      expect(person.displayName, 'Pulse user');
      expect(person.initials, 'PU');
      expect(person.avatarUrl, isNull);
    });

    test('the age of a block is arithmetic, never a guess', () {
      final now = DateTime(2026, 11, 14, 12);
      expect(
        _person(at: now.subtract(const Duration(seconds: 30)))
            .blockedLabel(now),
        'Blocked just now',
      );
      expect(
        _person(at: now.subtract(const Duration(minutes: 20)))
            .blockedLabel(now),
        'Blocked 20 min ago',
      );
      expect(
        _person(at: now.subtract(const Duration(hours: 5))).blockedLabel(now),
        'Blocked 5 h ago',
      );
      expect(
        _person(at: now.subtract(const Duration(days: 45))).blockedLabel(now),
        'Blocked 1 months ago',
      );
      expect(
        _person(at: now.subtract(const Duration(days: 400))).blockedLabel(now),
        'Blocked over a year ago',
      );
    });
  });

  group('unblocking', () {
    ProviderContainer containerWith(FakeProfileRepository repo) {
      final container = ProviderContainer(
        overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the row leaves at once and stays gone on the server', () async {
      final repo = FakeProfileRepository(
        blocked: [
          _person(id: 'u1'),
          _person(id: 'u2', name: 'Tania'),
        ],
      );
      final container = containerWith(repo);

      final rows = await container.read(blockedPeopleProvider.future);
      expect(rows.length, 2);

      final failure = await container
          .read(blockedPeopleProvider.notifier)
          .unblock(rows.first);

      expect(failure, isNull);
      expect(repo.unblockedId, 'u1');
      expect(repo.blocked.map((p) => p.id), ['u2']);
    });

    test('a server refusal puts the row back', () async {
      final repo = FakeProfileRepository(blocked: [_person(id: 'u1')])
        ..failUnblock = true;
      final container = containerWith(repo);

      await container.read(blockedPeopleProvider.future);
      final failure = await container
          .read(blockedPeopleProvider.notifier)
          .unblock(_person(id: 'u1'));

      expect(failure, isNotNull);
      expect(
        (container.read(blockedPeopleProvider).value ?? const []).length,
        1,
        reason: 'the page must never claim a block was lifted when it was not',
      );
      expect(repo.unblockedId, isNull);
    });
  });
}
