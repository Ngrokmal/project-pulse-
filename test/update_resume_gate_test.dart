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

  Widget harness({
    required AppUpdate? update,
    required Future<void> Function(WidgetTester tester) onEnter,
  }) {
    final router = GoRouter(
      initialLocation: '/app',
      routes: [
        GoRoute(
          path: '/app',
          builder: (context, state) => UpdateResumeGate(
            child: const Scaffold(body: Center(child: Text('THE APP'))),
          ),
        ),
        GoRoute(
          path: '/update',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('UPDATE PAGE'))),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        updateRepositoryProvider.overrideWithValue(_FakeRepo(update)),
        apkInstallerProvider.overrideWithValue(_FakeInstaller()),
        updateStoreProvider.overrideWith((ref) async => UpdateStore(temp)),
        installedBuildProvider.overrideWith(
          (ref) async =>
              const InstalledBuild(versionName: '0.1.41', versionCode: 41),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
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

  testWidgets('coming back to the app opens the update page', (tester) async {
    await tester.pumpWidget(
      harness(update: _manifest(43), onEnter: leaveAndComeBack),
    );
    await tester.pump();
    expect(find.text('THE APP'), findsOneWidget);

    await leaveAndComeBack(tester);

    expect(find.text('UPDATE PAGE'), findsOneWidget);
  });

  testWidgets('and it opens on every return, not just the first', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(update: _manifest(43), onEnter: leaveAndComeBack),
    );
    await tester.pump();

    await leaveAndComeBack(tester);
    expect(find.text('UPDATE PAGE'), findsOneWidget);

    // Back into the app (this is what "Not now" does)…
    GoRouter.of(tester.element(find.text('UPDATE PAGE'))).go('/app');
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
    await tester.pumpWidget(
      harness(update: _manifest(41), onEnter: leaveAndComeBack),
    );
    await tester.pump();

    await leaveAndComeBack(tester);

    expect(find.text('THE APP'), findsOneWidget);
    expect(find.text('UPDATE PAGE'), findsNothing);
  });

  testWidgets('no release channel means no interruption', (tester) async {
    await tester.pumpWidget(harness(update: null, onEnter: leaveAndComeBack));
    await tester.pump();

    await leaveAndComeBack(tester);

    expect(find.text('THE APP'), findsOneWidget);
  });
}
