import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/logging/app_logger.dart';

void main() {
  group('Logger redaction (§11 LOGGING — no secrets in logs)', () {
    test('redacts JWT shaped strings', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop';
      final out = AppLogger.redact('token=$jwt');
      expect(out.contains('eyJhbGciOiJIUzI1NiJ9'), isFalse);
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('redacts supabase style keys', () {
      final out = AppLogger.redact(
        'key=sb_publishable_EXAMPLEKEYnotarealkey123456789',
      );
      expect(out.contains('Lsjr3hEivHWrW64cSmCGAA'), isFalse);
    });

    test('redacts github style tokens', () {
      final out = AppLogger.redact('ghp_EXAMPLEEXAMPLEEXAMPLEEXAMPLETOKEN1234');
      expect(out.contains('OY4mQRAKzsunsdeI0PSEKmiJf'), isFalse);
    });

    test('redacts password pairs', () {
      final out = AppLogger.redact('{"password":"hunter2"}');
      expect(out.contains('hunter2'), isFalse);
    });

    test('keeps harmless text intact', () {
      expect(AppLogger.redact('sign in ok'), 'sign in ok');
    });
  });
}
