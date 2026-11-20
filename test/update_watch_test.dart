import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/update/application/update_controller.dart';
import 'package:pulse/features/update/application/update_watch.dart';
import 'package:pulse/features/update/data/apk_installer.dart';
import 'package:pulse/features/update/data/update_store.dart';
import 'package:pulse/features/update/domain/app_update.dart';
import 'package:pulse/features/update/domain/update_repository.dart';

/// A channel that can be told to fail, and that counts how often anyone asked.
class _Repo implements UpdateRepository {
  _Repo({this.update, this.failuresLeft = 0, this.delay});

  AppUpdate? update;
  int failuresLeft;
  int calls = 0;

  /// A slow release channel, for the budget tests.
  final Duration? delay;

  @override
  Future<AppUpdate?> latest() async {
    calls++;
    if (delay != null) await Future<void>.delayed(delay!);
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const SocketException('no route to host');
    }
    return update;
  }
}

class _Installer implements ApkInstaller {
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
      apkUrl: 'https://example.test/pulse-${deviceAbiKey()}.apk',
      sizeBytes: 1000,
      sha256: '0' * 64,
    ),
  },
);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pulse-watch-test'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ProviderContainer containerWith(_Repo repo, {int installedCode = 41}) {
    final container = ProviderContainer(
      overrides: [
        updateRepositoryProvider.overrideWithValue(repo),
        apkInstallerProvider.overrideWithValue(_Installer()),
        updateStoreProvider.overrideWith((ref) async => UpdateStore(temp)),
        installedBuildProvider.overrideWith(
          (ref) async => InstalledBuild(
            versionName: '0.1.$installedCode',
            versionCode: installedCode,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('cadence', () {
    const cadence = UpdateCadence(
      first: Duration(seconds: 3),
      max: Duration(seconds: 30),
      calm: Duration(minutes: 2),
    );

    test('an offered build stops the heartbeat', () {
      for (final phase in [
        UpdatePhase.available,
        UpdatePhase.downloading,
        UpdatePhase.ready,
        UpdatePhase.installing,
      ]) {
        expect(cadence.next(phase, failures: 0), isNull, reason: '$phase');
      }
    });

    test('a current build is re-checked calmly', () {
      expect(
        cadence.next(UpdatePhase.upToDate, failures: 0),
        const Duration(minutes: 2),
      );
    });

    test('a failure retries soon, then backs off to the ceiling', () {
      expect(cadence.next(UpdatePhase.failed, failures: 0), cadence.first);
      expect(
        cadence.next(UpdatePhase.failed, failures: 1),
        const Duration(seconds: 6),
      );
      expect(
        cadence.next(UpdatePhase.failed, failures: 2),
        const Duration(seconds: 12),
      );
      expect(
        cadence.next(UpdatePhase.failed, failures: 3),
        const Duration(seconds: 24),
      );
      expect(cadence.next(UpdatePhase.failed, failures: 4), cadence.max);
      expect(cadence.next(UpdatePhase.failed, failures: 40), cadence.max);
    });
  });

  group('one ask at a time', () {
    test('two callers share a single manifest call', () async {
      final repo = _Repo(update: _manifest(42));
      final container = containerWith(repo);
      final controller = container.read(updateControllerProvider.notifier);

      await Future.wait([controller.check(), controller.check()]);

      expect(repo.calls, 1);
      expect(
        container.read(updateControllerProvider).phase,
        UpdatePhase.available,
      );
    });

    test(
      'a launch ask that misses its budget is joined, not repeated',
      () async {
        // A cold TLS handshake: slower than the launch budget, well inside the
        // heartbeat's.
        final repo = _Repo(
          update: _manifest(42),
          delay: const Duration(milliseconds: 60),
        );
        final container = containerWith(repo);
        final controller = container.read(updateControllerProvider.notifier);

        await controller.checkAtBoot(budget: const Duration(milliseconds: 1));
        expect(
          container.read(updateControllerProvider).phase,
          UpdatePhase.idle,
        );

        // The heartbeat's first beat, a moment later, must join it.
        await controller.check();
        expect(repo.calls, 1);
        expect(
          container.read(updateControllerProvider).phase,
          UpdatePhase.available,
        );
      },
    );
  });

  group('the heartbeat', () {
    test('a failed first ask retries itself and finds the update', () {
      fakeAsync((async) {
        final repo = _Repo(update: _manifest(42), failuresLeft: 1);
        final container = containerWith(repo);
        final watch = UpdateWatch(
          container.read,
          budget: const Duration(seconds: 10),
        );

        watch.start();
        async.flushMicrotasks();
        expect(repo.calls, 1);
        expect(
          container.read(updateControllerProvider).phase,
          UpdatePhase.failed,
        );

        // The first retry is three seconds out.
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();

        expect(repo.calls, 2);
        expect(
          container.read(updateControllerProvider).phase,
          UpdatePhase.available,
        );
        expect(
          container.read(updateControllerProvider).shouldPrompt,
          isTrue,
          reason: 'the page is offered without anyone touching the app',
        );
        expect(watch.isWatching, isFalse, reason: 'it stops once it has news');
      });
    });

    test('a current build keeps a slow beat instead of stopping', () {
      fakeAsync((async) {
        final repo = _Repo(update: _manifest(41));
        final container = containerWith(repo);
        final watch = UpdateWatch(
          container.read,
          budget: const Duration(seconds: 10),
        );

        watch.start();
        async.flushMicrotasks();
        expect(
          container.read(updateControllerProvider).phase,
          UpdatePhase.upToDate,
        );

        async.elapse(const Duration(minutes: 2, seconds: 1));
        async.flushMicrotasks();
        expect(
          repo.calls,
          2,
          reason: 'a release can land while the app is open',
        );

        watch.stop();
        async.elapse(const Duration(minutes: 10));
        expect(repo.calls, 2, reason: 'and stopping really stops');
      });
    });
  });
}
