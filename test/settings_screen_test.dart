import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/notifications/domain/push_token.dart';
import 'package:pulse/features/settings/domain/app_settings.dart';
import 'package:pulse/features/settings/domain/notification_settings_probe.dart';
import 'package:pulse/features/settings/presentation/settings_screen.dart';

/// The settings screen has to tell the truth about permissions: granted, never
/// asked, declined, blocked and unsupported all read differently, and only the
/// states that can still be changed offer a button.
void main() {
  Widget wrap(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: SettingsScreen()),
  );

  Future<void> pumpWith(
    WidgetTester tester,
    PushPermission permission, {
    PushPermission? afterRequest,
    InMemorySettingsStore? store,
  }) async {
    await tester.pumpWidget(
      wrap(
        ProviderContainer(
          overrides: [
            settingsStoreProvider.overrideWithValue(
              store ?? InMemorySettingsStore(),
            ),
            notificationProbeProvider.overrideWithValue(
              FakeNotificationSettingsProbe(
                permission,
                afterRequest: afterRequest,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('granted: says so and offers no pointless action', (
    tester,
  ) async {
    await pumpWith(tester, PushPermission.granted);
    expect(find.text('Notifications are on'), findsOneWidget);
    expect(find.text('Turn on'), findsNothing);
    expect(find.text('Ask again'), findsNothing);
  });

  testWidgets('never asked: explains and offers Turn on', (tester) async {
    await pumpWith(tester, PushPermission.notRequested);
    expect(find.text('Notifications are off'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
  });

  testWidgets('denied: explains and offers Ask again', (tester) async {
    await pumpWith(tester, PushPermission.denied);
    expect(find.text('Notifications are off'), findsOneWidget);
    expect(find.text('Ask again'), findsOneWidget);
  });

  testWidgets('declining again keeps it off and says why', (tester) async {
    await pumpWith(
      tester,
      PushPermission.denied,
      afterRequest: PushPermission.denied,
    );
    await tester.tap(find.text('Ask again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Notifications are off'), findsOneWidget);
    expect(
      find.textContaining('Notifications stay off'),
      findsOneWidget,
      reason: 'the user is told the outcome, not left guessing',
    );
  });

  testWidgets(
    'permanently denied: points at the system settings, no in-app retry',
    (tester) async {
      await pumpWith(tester, PushPermission.permanentlyDenied);
      expect(find.text('Notifications are blocked'), findsOneWidget);
      expect(find.textContaining('phone settings'), findsOneWidget);
      expect(find.text('Open system settings'), findsOneWidget);
      expect(find.text('Ask again'), findsNothing);
    },
  );

  testWidgets('unsupported build says push is unavailable, honestly', (
    tester,
  ) async {
    await pumpWith(tester, PushPermission.unsupported);
    expect(find.text('Notifications are unavailable'), findsOneWidget);
    expect(find.textContaining('Firebase did not initialise'), findsOneWidget);
  });

  testWidgets('toggling a preference writes it to the store', (tester) async {
    final store = InMemorySettingsStore();
    await pumpWith(tester, PushPermission.granted, store: store);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('settings-sounds')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect((await store.read()).soundsEnabled, isFalse);
  });

  testWidgets(
    'text size is exposed with a semantics value for screen readers',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWith(tester, PushPermission.granted);
      await tester.pump(const Duration(milliseconds: 100));
      final node = tester.getSemantics(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Text size',
        ),
      );
      expect(node.value, '100 percent');
      handle.dispose();
    },
  );
}
