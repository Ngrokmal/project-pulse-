import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pulse/features/update/application/update_controller.dart';
import 'package:pulse/features/update/data/apk_installer.dart';
import 'package:pulse/features/update/data/update_store.dart';
import 'package:pulse/features/update/domain/app_update.dart';
import 'package:pulse/features/update/domain/update_repository.dart';
import 'package:pulse/features/update/presentation/widgets/update_resume_gate.dart';

/// Does the update page really come back?
///
/// The user's rule: every time the app is entered, ask again. A cold start is
/// covered by the splash check (`checkAtBoot`), and coming back to the app is
/// covered by [UpdateResumeGate]. These tests drive the second half — the one
/// that used to be silently skipped because "later" was written to disk.
class _FakeRepo implements UpdateRepository {
  _FakeRepo(this.update);

  final AppUpdate? update;

  @override
  Future<AppUpdate?> latest() async => update;
}

class _FakeInstaller implements ApkInstaller {
  @override
  Future<bool> canInstall() async => true;

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<void> install(String apkPath) async {}
}

AppUpdate _manifest(int code) => AppUpdate(
  versionName: '0.1.$code',
  versionCode: code,
  channelBuild: code,
  variants: <String, UpdateVariant>{
    deviceAbiKey(): UpdateVariant(
      apkUrl: 'https://example.test/pulse.apk',
      sizeBytes: 4096,
      sha256: 'a' * 64,
    ),
  },
);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pulse_gate_'));
  tearDown(() => temp.deleteSync(recursive: true));

  /// The gate is mounted **where the app mounts it** — inside
  /// `MaterialApp.router`'s builder, above the router's inherited scope.
  ///
  /// The version of this harness that put the gate inside a *route* was the
  /// reason a white screen shipped: `GoRouter.of(context)` resolves in a route
  /// and throws in the builder, so the tests were green and the phone was blank.
  Widget harness({required AppUpdate? update, required GoRouter router}) {
    return ProviderScope(
      overrides: [
        updateRepositoryProvider.overrideWithValue(_FakeRepo(update)),
        apkInstallerProvider.overrideWithValue(_FakeInstaller()),
        updateStoreProvider.overrideWith((ref) async => UpdateStore(temp)),
        installedBuildProvider.overrideWith(
          (ref) async => const InstalledBuild(
            versionName: '0.1.41',
            versionCode: 41,
            channelBuild: 41,
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => UpdateResumeGate(
          routes: router.routerDelegate,
          location: () => router.routerDelegate.currentConfiguration.uri.path,
          openUpdate: () => router.go('/update'),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  GoRouter routerAt(String location) {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('SPLASH'))),
        ),
        GoRoute(
          path: '/welcome',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('WELCOME'))),
        ),
        GoRoute(
          path: '/app',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('THE APP'))),
        ),
        GoRoute(
          path: '/update',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('UPDATE PAGE'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    return router;
  }

  Future<void> leaveAndComeBack(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // One frame for the observer's post-frame callback, one for the check.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the gate mounts above the router without throwing', (
    tester,
  ) async {
    final router = routerAt('/app');
    await tester.pumpWidget(harness(update: null, router: router));
    await tester.pump();

    // This is the white-screen regression: a throw here renders nothing at all.
    expect(tester.takeException(), isNull);
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('the way into an account is never interrupted', (tester) async {
    final router = routerAt('/welcome');
    await tester.pumpWidget(harness(update: _manifest(43), router: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.text('UPDATE PAGE'), findsNothing);
  });

  testWidgets('an update already on offer is shown as soon as we are in', (
    tester,
  ) async {
    // A release that landed while the sign-in screens were up: the heartbeat
    // finds it, and entering the app opens the page without a resume.
    final router = routerAt('/app');
    await tester.pumpWidget(harness(update: _manifest(43), router: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('UPDATE PAGE'), findsOneWidget);
  });

  testWidgets('coming back to the app opens the update page', (tester) async {
    final router = routerAt('/app');
    await tester.pumpWidget(harness(update: _manifest(43), router: router));
    await tester.pump();
    expect(find.text('THE APP'), findsOneWidget);

    await leaveAndComeBack(tester);

    expect(find.text('UPDATE PAGE'), findsOneWidget);
  });

  testWidgets('and it opens on every return, not just the first', (
    tester,
  ) async {
    final router = routerAt('/app');
    await tester.pumpWidget(harness(update: _manifest(43), router: router));
    await tester.pump();

    await leaveAndComeBack(tester);
    expect(find.text('UPDATE PAGE'), findsOneWidget);

    // Back into the app (this is what "Not now" does)…
    router.go('/app');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('THE APP'), findsOneWidget);

    // …leave, come back: the page is offered again.
    await leaveAndComeBack(tester);
    expect(find.text('UPDATE PAGE'), findsOneWidget);
  });

  testWidgets('a build that is already current never interrupts', (
    tester,
  ) async {
    final router = routerAt('/app');
    await tester.pumpWidget(harness(update: _manifest(41), router: router));
    await tester.pump();

    await leaveAndComeBack(tester);

    expect(find.text('THE APP'), findsOneWidget);
    expect(find.text('UPDATE PAGE'), findsNothing);
  });

  testWidgets('no release channel means no interruption', (tester) async {
    final router = routerAt('/app');
    await tester.pumpWidget(harness(update: null, router: router));
    await tester.pump();

    await leaveAndComeBack(tester);

    expect(find.text('THE APP'), findsOneWidget);
  });
}
