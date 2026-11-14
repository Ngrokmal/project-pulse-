import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/profile/domain/profile.dart';

void main() {
  group('Profile.fromMap', () {
    test('parses a full row', () {
      final p = Profile.fromMap({
        'id': 'u1',
        'display_name': 'Ngrok Use',
        'username': 'ngrokuse',
        'bio': 'Dream big',
        'avatar_url': null,
        'cover_url': null,
        'joined_at': '2025-11-01T10:00:00Z',
      });
      expect(p.id, 'u1');
      expect(p.displayName, 'Ngrok Use');
      expect(p.username, 'ngrokuse');
      expect(p.bio, 'Dream big');
      expect(p.joinedAt, isNotNull);
    });

    test('tolerates nulls the database allows', () {
      final p = Profile.fromMap({
        'id': 'u2',
        'display_name': '',
        'joined_at': null,
      });
      expect(p.username, isNull);
      expect(p.bio, '');
      expect(p.joinedAt, isNull);
    });
  });

  group('validation mirrors DB constraints (0001_profiles.sql)', () {
    test('username rules: 3-24 chars, lowercase/numbers/underscore', () {
      expect(Profile.validateUsername('abc'), isNull);
      expect(Profile.validateUsername('ab'), isNotNull);
      expect(Profile.validateUsername('a' * 25), isNotNull);
      expect(Profile.validateUsername('Has Space'), isNotNull);
      expect(Profile.validateUsername('bad!char'), isNotNull);
      expect(
        Profile.validateUsername(''),
        isNull,
        reason: 'username is optional',
      );
    });

    test('normalizeUsername lowercases and trims', () {
      expect(Profile.normalizeUsername('  NgrokUse '), 'ngrokuse');
    });

    test('display name length limit is 60', () {
      expect(Profile.validateDisplayName('ok'), isNull);
      expect(Profile.validateDisplayName(''), isNotNull);
      expect(Profile.validateDisplayName('x' * 61), isNotNull);
    });

    test('bio length limit is 200', () {
      expect(Profile.validateBio('x' * 200), isNull);
      expect(Profile.validateBio('x' * 201), isNotNull);
    });
  });

  group('initials', () {
    test('two words → two initials', () {
      const p = Profile(id: 'u', displayName: 'Ngrok Use');
      expect(p.initials, 'NU');
    });

    test('falls back to username / placeholder', () {
      expect(
        const Profile(id: 'u', displayName: '', username: 'abc').initials,
        'A',
      );
      expect(const Profile(id: 'u', displayName: '').initials, '?');
    });
  });
}
