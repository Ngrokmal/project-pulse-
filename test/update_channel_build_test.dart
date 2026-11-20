import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/update/application/update_controller.dart';
import 'package:pulse/features/update/data/apk_installer.dart';
import 'package:pulse/features/update/data/update_store.dart';
import 'package:pulse/features/update/domain/app_update.dart';
import 'package:pulse/features/update/domain/update_repository.dart';

/// The update channel's identity, and the bug that hid it.
///
/// **What went wrong.** `flutter build apk --split-per-abi` gives each slice a
/// `versionCode` of `ABI_INDEX * 1000 + build`: arm64 build 48 installs as
/// **2048**. The release manifest published the build number it was named
/// after — `versionCode: 48`. The app compared the two, decided `48 > 2048` was
/// false, and reported "you are up to date" on every launch of every build.
/// Builds 46, 47, 48, 49 and 50 were published and never once offered.
///
/// Not a SHA mismatch, not a keystore mismatch, not malformed JSON: the two
/// sides were each internally correct and meant different things by the same
/// word. The fix is one number that means the same thing everywhere
/// (`channelBuild`), with the APK's own `versionCode` published alongside it so
/// a phone can recognise the exact file it is running.
///
/// These tests are the fence around that.
class _Repo implements UpdateRepository {
  _Repo(this.update);
  final AppUpdate? update;

  @override
  Future<AppUpdate?> latest() async => update;
}

class _Installer implements ApkInstaller {
  @override
  Future<bool> canInstall() async => true;

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<void> install(String apkPath) async {}
}

/// A manifest exactly as `tool/release_manifest.py` writes it for run [run].
///
/// The host's own ABI is included as well, because the tests run on x64 CI
/// machines while the channel ships phones — an ABI the device does not have is
/// correctly ignored, and that would hide the decision under test.
Map<String, Object?> manifestFor(int run) {
  const base = 'https://github.com/example/pulse/releases/latest/download';

  /// Android's own ABI table, which is where the `* 1000` comes from.
  const abiIndex = <String, int>{'arm64': 2, 'arm32': 1, 'x86': 3, 'x64': 4};

  Map<String, Object?> slice(String abi) => <String, Object?>{
    'apkUrl': '$base/pulse-$abi.apk',
    'sizeBytes': abi == 'arm32' ? 25000000 : 29593972,
    'sha256': abi == 'arm32' ? 'b' * 64 : 'a' * 64,
    'versionCode': abiIndex[abi]! * 1000 + run,
  };

  final abis = <String, Object?>{
    for (final abi in abiIndex.keys) abi: slice(abi),
  };

  return <String, Object?>{
    'versionName': '0.1.$run',
    'channelBuild': run,
    'versionCode': 2000 + run,
    'publishedAt': '2026-11-20T10:00:00Z',
    'apkUrl': '$base/pulse-arm64.apk',
    'sizeBytes': 29593972,
    'sha256': 'a' * 64,
    'abis': abis,
    'notes': <String>['A build'],
  };
}

void main() {
  group('the build number Android reports is not the build number', () {
    test('per-ABI split codes are unwrapped, not taken at face value', () {
      // The values read out of the real published APKs.
      expect(channelBuildFromVersionCode(2046), 46);
      expect(channelBuildFromVersionCode(2048), 48);
      expect(channelBuildFromVersionCode(2050), 50);
      expect(channelBuildFromVersionCode(1048), 48);
      expect(channelBuildFromVersionCode(1050), 50);
      // A universal APK, and anything from before splitting, is already a build
      // number.
      expect(channelBuildFromVersionCode(46), 46);
      expect(channelBuildFromVersionCode(1), 1);
    });

    test('an installed build knows its own number without arithmetic', () {
      const build = InstalledBuild(
        versionName: '0.1.50',
        versionCode: 2050,
        channelBuild: 50,
      );
      expect(build.label, 'v0.1.50 · build 50');
    });
  });

  group('the decision that was broken', () {
    test('build 48 (installed as 2048) is offered build 50', () {
      final update = AppUpdate.tryParse(manifestFor(50))!;
      final installed = InstalledBuild(
        versionName: '0.1.48',
        versionCode: 2048,
        channelBuild: channelBuildFromVersionCode(2048),
      );

      // This is the assertion that would have failed for six builds in a row.
      expect(
        update.isNewerThan(
          installed.channelBuild,
          abi: 'arm64',
          installedVersionCode: installed.versionCode,
        ),
        isTrue,
        reason: '48 must see 50 — that is the whole point',
      );
    });

    test('a phone already running the release is not offered it', () {
      final update = AppUpdate.tryParse(manifestFor(50))!;
      expect(update.isNewerThan(50, installedVersionCode: 2050), isFalse);
      expect(update.carriesVersionCode(2050), isTrue);
      expect(update.carriesVersionCode(2048), isFalse);
    });

    test('an older channel never offers itself over a newer install', () {
      final update = AppUpdate.tryParse(manifestFor(50))!;
      expect(update.isNewerThan(51), isFalse);
    });

    test('a manifest without channelBuild still compares as a build number', () {
      // Every release before this fix looked like this; the fallback is why an
      // installed copy can still update itself.
      final legacy = AppUpdate.tryParse(<String, Object?>{
        'versionName': '0.1.50',
        'versionCode': 50,
        'apkUrl': 'https://example.test/pulse.apk',
        'sizeBytes': 1024,
        'sha256': 'a' * 64,
      })!;
      expect(legacy.channelBuild, 50);
      expect(legacy.isNewerThan(48), isTrue);
    });
  });

  group('one last hop for copies that are already out there', () {
    test(
      'the published versionCode is newer than an installed split build',
      () {
        // A build shipped before this fix compares the *flat* versionCode. It runs
        // 2048, so the manifest publishing 2051 is what lets it update itself
        // without a manual reinstall.
        final update = AppUpdate.tryParse(manifestFor(51))!;
        expect(update.versionCode, 2051);
        expect(update.versionCode > 2048, isTrue);
        expect(update.versionCode > 1048, isTrue, reason: 'armv7 too');
      },
    );
  });

  group('the controller reaches the update page', () {
    Future<ProviderContainer> harness(AppUpdate? manifest) async {
      final temp = await Directory.systemTemp.createTemp('pulse-update-test');
      addTearDown(() => temp.delete(recursive: true));
      final container = ProviderContainer(
        overrides: [
          updateRepositoryProvider.overrideWithValue(_Repo(manifest)),
          apkInstallerProvider.overrideWithValue(_Installer()),
          updateStoreProvider.overrideWith((ref) async => UpdateStore(temp)),
          installedBuildProvider.overrideWith(
            (ref) async => const InstalledBuild(
              versionName: '0.1.48',
              versionCode: 2048,
              channelBuild: 48,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an update published for a newer build appears', () async {
      final container = await harness(AppUpdate.tryParse(manifestFor(50)));
      await container.read(updateControllerProvider.notifier).check();
      final state = container.read(updateControllerProvider);

      expect(state.phase, UpdatePhase.available);
      expect(state.shouldPrompt, isTrue);
      expect(state.variant, isNotNull);
      expect(state.update!.channelBuild, 50);
    });

    test('the newest build keeps the app quiet', () async {
      final container = await harness(AppUpdate.tryParse(manifestFor(48)));
      await container.read(updateControllerProvider.notifier).check();
      expect(
        container.read(updateControllerProvider).phase,
        UpdatePhase.upToDate,
      );
      expect(container.read(updateControllerProvider).shouldPrompt, isFalse);
    });
  });

  group('the manifest CI writes', () {
    test('survives a JSON round trip, notes and all', () {
      final text = jsonEncode(manifestFor(51));
      final update = AppUpdate.tryParse(jsonDecode(text))!;
      expect(update.versionName, '0.1.51');
      expect(update.channelBuild, 51);
      expect(update.variantFor('arm64')!.versionCode, 2051);
      expect(update.variantFor('arm32')!.versionCode, 1051);
      expect(update.notes, <String>['A build']);
    });

    test('every slice carries the code its APK really has', () {
      for (final run in <int>[51, 52, 99, 999]) {
        final update = AppUpdate.tryParse(manifestFor(run))!;
        expect(update.variantFor('arm64')!.versionCode, 2000 + run);
        expect(update.variantFor('arm32')!.versionCode, 1000 + run);
      }
    });
  });
}
