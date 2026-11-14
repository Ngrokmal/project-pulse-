import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/auth/application/auth_controller.dart';
import 'package:pulse/features/auth/domain/auth_repository.dart';
import 'package:pulse/features/auth/presentation/auth_screen.dart';

class _FakeAuthRepository implements AuthRepository {
  int signInCalls = 0;

  @override
  Future<AuthOutcome?> restoreSession() async => null;

  @override
  Future<AuthSuccess> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    throw const AuthFailure(
      'Email or password is incorrect.',
      kind: AuthFailureKind.invalidCredentials,
    );
  }

  @override
  Future<AuthSuccess> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async => AuthSuccess(
    user: PulseUser(id: 'u1', email: email, displayName: displayName),
  );

  @override
  Future<void> signOut() async {}

  @override
  Stream<PulseUser?> authStateChanges() => const Stream.empty();
}

Widget _wrap(Widget child, AuthRepository repo) => ProviderScope(
  overrides: [authRepositoryProvider.overrideWithValue(repo)],
  child: MaterialApp(theme: ThemeData(useMaterial3: true), home: child),
);

void main() {
  testWidgets('validation blocks an empty submit and shows field errors', (
    tester,
  ) async {
    final repo = _FakeAuthRepository();
    await tester.pumpWidget(_wrap(const AuthScreen(startInSignup: true), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
    // No network call may happen when the form is invalid.
    expect(repo.signInCalls, 0);
  });

  testWidgets('invalid email format is rejected', (tester) async {
    final repo = _FakeAuthRepository();
    await tester.pumpWidget(_wrap(const AuthScreen(), repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('login failure surfaces a typed, readable error', (tester) async {
    final repo = _FakeAuthRepository();
    await tester.pumpWidget(_wrap(const AuthScreen(), repo));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(repo.signInCalls, 1);
  });
}
