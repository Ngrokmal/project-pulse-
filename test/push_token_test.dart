import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/notifications/data/push_messaging_service.dart';
import 'package:pulse/features/notifications/domain/push_token.dart';
import 'package:pulse/features/notifications/domain/push_token_repository.dart';

const _realLookingToken =
    'dGVzdC1saXZlLWFwaS0wMTIzNDU2Nzg5YWJjZGVmMDEyMzQ1Njc4OWFiY2RlZg';

void main() {
  group('PushToken.validate mirrors the fcm_tokens_len DB CHECK', () {
    test('accepts a realistic 60+ character token', () {
      expect(PushToken.validate(_realLookingToken), isNull);
      expect(PushToken.tryParse(_realLookingToken)!.value, _realLookingToken);
    });

    test('rejects null (Firebase returned nothing)', () {
      expect(PushToken.validate(null), contains('No push token'));
      expect(PushToken.tryParse(null), isNull);
    });

    test('rejects tokens shorter than 20 characters', () {
      expect(PushToken.validate('tooshort'), contains('too short'));
      expect(PushToken.validate('x' * 19), isNotNull);
      expect(PushToken.validate('x' * 20), isNull);
    });

    test('rejects tokens longer than 4096 characters', () {
      expect(PushToken.validate('x' * 4096), isNull);
      expect(PushToken.validate('x' * 4097), contains('too long'));
    });

    test('rejects whitespace inside a token', () {
      expect(PushToken.validate('${'a' * 25} b'), contains('whitespace'));
      expect(PushToken.validate('  ${'a' * 25}  '), isNull, reason: 'trimmed');
    });

    test('rejects an empty string', () {
      expect(PushToken.validate(''), isNotNull);
      expect(PushToken.validate('    '), isNotNull);
    });
  });

  group('PushPermission', () {
    test('only granted can deliver', () {
      expect(PushPermission.granted.canDeliver, isTrue);
      for (final p in [
        PushPermission.notRequested,
        PushPermission.denied,
        PushPermission.permanentlyDenied,
        PushPermission.unsupported,
      ]) {
        expect(p.canDeliver, isFalse, reason: p.name);
      }
    });

    test('Firebase authorization statuses map 1:1', () {
      expect(
        PushMessagingService.mapStatus(AuthorizationStatus.authorized),
        PushPermission.granted,
      );
      expect(
        PushMessagingService.mapStatus(AuthorizationStatus.provisional),
        PushPermission.granted,
      );
      expect(
        PushMessagingService.mapStatus(AuthorizationStatus.denied),
        PushPermission.denied,
      );
      expect(
        PushMessagingService.mapStatus(AuthorizationStatus.deniedPermanently),
        PushPermission.permanentlyDenied,
      );
      expect(
        PushMessagingService.mapStatus(AuthorizationStatus.notDetermined),
        PushPermission.notRequested,
      );
    });
  });

  group('failure mapping', () {
    test('a token owned by another account becomes a typed server failure', () {
      final failure = asFailure(const TokenOwnedByAnotherAccount());
      expect(failure, isA<ServerFailure>());
      expect(failure.code, 'push_token_foreign');
      expect(failure.userMessage, isNotEmpty);
    });

    test('AppFailure passes through untouched', () {
      const original = ServerFailure(safeCode: 'push_token_unavailable');
      expect(asFailure(original), same(original));
    });

    test('unknown errors never leak their text to the user', () {
      final failure = asFailure(StateError('database exploded: secret'));
      expect(failure.code, 'push_sync_failed');
      expect(failure.userMessage.toLowerCase(), isNot(contains('secret')));
    });
  });
}
