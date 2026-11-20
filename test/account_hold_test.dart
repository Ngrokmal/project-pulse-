import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/account_status/application/account_status_controller.dart';
import 'package:pulse/features/account_status/domain/account_status.dart';
import 'package:pulse/features/account_status/presentation/account_on_hold_screen.dart';
import 'package:pulse/features/account_status/presentation/widgets/held_orrery.dart';
import 'package:pulse/features/auth/application/auth_controller.dart';
import 'package:pulse/features/auth/domain/auth_repository.dart';

/// A lock controller whose logout can be observed without a Supabase client.
class _SpyLockController extends AccountLockController {
  int signOuts = 0;

  @override
  Future<void> endSession() async {
    signOuts++;
  }
}

const _suspended = AccountStatusInfo(
  state: AccountState.suspended,
  reasonText: 'Reported by three people for sending the same link in groups.',
  caseCode: 'PULSE-7F2C-91A4B',
);

void main() {
  group('the hold', () {
    test('carries the case code and the masked email the notice prints', () {
      final hold = AccountHold(
        info: _suspended,
        since: DateTime(2026, 11, 20),
        email: 'hasan.ahmed@gmail.com',
      );
      expect(hold.info.caseCode, 'PULSE-7F2C-91A4B');
      expect(hold.maskedEmail, 'ha•••••@gmail.com');
    });

    test('an open-ended hold never invents a date', () {
      expect(_suspended.isOpenEnded, isTrue);
      expect(_suspended.commitment, isNot(contains('2026')));
      expect(_suspended.commitment.toLowerCase(), contains('person'));
    });

    test('a windowed hold prints the window', () {
      final windowed = AccountStatusInfo(
        state: AccountState.suspended,
        endsAt: DateTime(2026, 11, 23, 9),
      );
      expect(windowed.isOpenEnded, isFalse);
      expect(windowed.commitment, contains('23 Nov 2026'));
    });

    test('the headline never says "paused" for a closed account', () {
      const closed = AccountStatusInfo(state: AccountState.banned);
      expect(closed.headlineAccent, 'closed.');
    });
  });

  group('the lock', () {
    test('ends the session exactly once, however often it is told', () async {
      final container = ProviderContainer(
        overrides: [accountLockProvider.overrideWith(_SpyLockController.new)],
      );
      addTearDown(container.dispose);

      final lock = container.read(accountLockProvider.notifier);
      await lock.lock(_suspended);
      await lock.lock(_suspended);
      await lock.lock(_suspended);

      expect((lock as _SpyLockController).signOuts, 1);
      expect(
        container.read(accountLockProvider)?.info.caseCode,
        'PULSE-7F2C-91A4B',
      );
    });

    test('an active account never locks the app', () async {
      final container = ProviderContainer(
        overrides: [accountLockProvider.overrideWith(_SpyLockController.new)],
      );
      addTearDown(container.dispose);

      await container
          .read(accountLockProvider.notifier)
          .lock(AccountStatusInfo.activeInfo);
      expect(container.read(accountLockProvider), isNull);
    });

    test(
      'signing in to appeal defers the logout until the appeal is filed',
      () async {
        final container = ProviderContainer(
          overrides: [accountLockProvider.overrideWith(_SpyLockController.new)],
        );
        addTearDown(container.dispose);

        final lock = container.read(accountLockProvider.notifier);
        lock.beginAppealSession();
        await lock.lock(_suspended);
        expect(
          (lock as _SpyLockController).signOuts,
          0,
          reason: 'the appeal needs the session it just opened',
        );

        await lock.endAppealSession();
        expect(lock.signOuts, 1);
      },
    );

    test('"a different account" clears the hold', () async {
      final container = ProviderContainer(
        overrides: [accountLockProvider.overrideWith(_SpyLockController.new)],
      );
      addTearDown(container.dispose);

      final lock = container.read(accountLockProvider.notifier);
      await lock.lock(_suspended);
      lock.clear();
      expect(container.read(accountLockProvider), isNull);
    });
  });

  group('the notice', () {
    testWidgets('renders the case, the reason and the one way out', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          accountLockProvider.overrideWith(
            () => _FixedLock(
              AccountHold(
                info: _suspended,
                since: DateTime(2026, 11, 20),
                email: 'hasan.ahmed@gmail.com',
              ),
            ),
          ),
          authControllerProvider.overrideWith(_StubAuth.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountOnHoldScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('ACCOUNT ON HOLD'), findsOneWidget);
      expect(find.textContaining('ha•••••@gmail.com'), findsWidgets);
      expect(find.text('PULSE-7F2C-91A4B'), findsOneWidget);
      expect(find.text('Ask a person to look again'), findsOneWidget);
      expect(find.text('Sign in with a different account'), findsOneWidget);

      // The seal is the animation, and it is on screen.
      expect(find.byType(HeldOrrery), findsOneWidget);
    });
  });
}

class _FixedLock extends AccountLockController {
  _FixedLock(this._hold);

  final AccountHold _hold;

  @override
  AccountHold? build() => _hold;

  @override
  Future<void> endSession() async {}
}

class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthSignedOut();
}

/// Kept so the imported identity type is exercised the way the real app uses it
/// (the notice reads the email from the session at the instant of the hold).
const _identity = PulseUser(id: 'u1', email: 'hasan.ahmed@gmail.com');
// ignore: unused_element
PulseUser get _exampleIdentity => _identity;
