import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/admin/application/admin_providers.dart';
import 'package:pulse/features/admin/domain/admin_repository.dart';
import 'package:pulse/features/admin/presentation/admin_screen.dart';
import 'package:pulse/features/auth/application/auth_controller.dart';
import 'package:pulse/features/auth/domain/auth_repository.dart';

class _SignedInController extends AuthController {
  @override
  AuthState build() => const AuthSignedIn(
    PulseUser(id: 'admin', email: 'admin@example.invalid'),
  );

  void switchTo(String id) =>
      state = AuthSignedIn(PulseUser(id: id, email: null));
  void signOutForTest() => state = const AuthSignedOut();
}

class _FakeAdminRepository implements AdminRepository {
  bool canSend = true;
  int listCalls = 0;
  @override
  Future<bool> isAdmin() async => true;
  @override
  Future<List<ManagedUser>> users({String query = '', int offset = 0}) async {
    listCalls++;
    return [
      ManagedUser(
        id: 'user-1',
        email: 'test@example.invalid',
        displayName: 'Test person',
        status: 'active',
        canSendMessages: canSend,
        canStartCalls: true,
        canChangeProfilePhoto: true,
      ),
    ];
  }

  @override
  Future<void> setControl(String userId, String control, bool enabled) async {
    if (control == 'send_messages') canSend = enabled;
  }

  @override
  Future<void> setErrorMessage(String code, String message) async {}
  @override
  Future<void> setSuspension(
    String userId,
    bool suspended, {
    DateTime? until,
  }) async {}
}

void main() {
  testWidgets('non-admin sees no account data or controls', (tester) async {
    final repo = _FakeAdminRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAccessProvider.overrideWith((ref) async => false),
          adminRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(find.text('Test person'), findsNothing);
    expect(repo.listCalls, 0);
  });

  testWidgets('authorised account loads controls and saves a change', (
    tester,
  ) async {
    final repo = _FakeAdminRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAccessProvider.overrideWith((ref) async => true),
          authControllerProvider.overrideWith(_SignedInController.new),
          adminRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Test person'), findsOneWidget);
    await tester.tap(find.text('Test person'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Can send messages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(repo.canSend, isFalse);
    expect(repo.listCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('account switch resets workspace and sign out hides it', (
    tester,
  ) async {
    final repo = _FakeAdminRepository();
    final container = ProviderContainer(
      overrides: [
        adminAccessProvider.overrideWith((ref) async => true),
        authControllerProvider.overrideWith(_SignedInController.new),
        adminRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Test person'), findsOneWidget);
    final controller =
        container.read(authControllerProvider.notifier) as _SignedInController;
    controller.switchTo('another-admin');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(repo.listCalls, 2);
    controller.signOutForTest();
    await tester.pump();
    expect(find.text('Test person'), findsNothing);
    expect(find.text('Administrator access is required.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('verification failure is not shown as successful access', (
    tester,
  ) async {
    final repo = _FakeAdminRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAccessProvider.overrideWith(
            (ref) async => throw StateError('offline'),
          ),
          adminRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Could not verify administrator access.'), findsOneWidget);
    expect(repo.listCalls, 0);
  });
}
