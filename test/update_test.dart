import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/features/update/application/update_controller.dart';
import 'package:pulse/features/update/data/apk_installer.dart';
import 'package:pulse/features/update/data/update_store.dart';
import 'package:pulse/features/update/domain/app_update.dart';
import 'package:pulse/features/update/domain/update_repository.dart';

import 'package:crypto/crypto.dart';

/// The update channel, as four promises:
///   1. an unusable manifest is never treated as an update,
///   2. the build number decides, nothing else,
///   3. a downloaded, verified APK is never downloaded again,
///   4. an APK whose bytes do not match the published hash is thrown away.
class _FakeRepo implements UpdateRepository {
  _FakeRepo(this.update);
  final AppUpdate? update;
  int calls = 0;

  @override
  Future<AppUpdate?> latest() async {
    calls++;
    return update;
  }
}

class _FakeInstaller implements ApkInstaller {
  _FakeInstaller({this.allowed = true});
  bool allowed;
  final List<String> installed = <String>[];

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<void> install(String apkPath) async => installed.add(apkPath);
}

/// A manifest for this host's ABI, plus a decoy for the other one, so the tests
/// also prove the device picks its own file.
AppUpdate _manifest({required String sha, required int size, int code = 42}) {
  final mine = deviceAbiKey();
  final other = mine == 'arm64' ? 'arm32' : 'arm64';
  return AppUpdate(
    versionName: '0.1.$code',
    versionCode: code,
    notes: const <String>['One thing changed'],
    variants: <String, UpdateVariant>{
      mine: UpdateVariant(
        apkUrl: 'https://example.test/pulse-$mine.apk',
        sizeBytes: size,
        sha256: sha,
      ),
      other: UpdateVariant(
        apkUrl: 'https://example.test/pulse-$other.apk',
        sizeBytes: size * 3,
        sha256: '0' * 64,
      ),
    },
  );
}

/// The old, universal shape every release before per-ABI splitting used.
AppUpdate _flatManifest({
  required String sha,
  required int size,
  int code = 42,
}) => AppUpdate(
  versionName: '0.1.$code',
  versionCode: code,
  variants: <String, UpdateVariant>{
    'universal': UpdateVariant(
      apkUrl: 'https://example.test/pulse.apk',
      sizeBytes: size,
      sha256: sha,
    ),
  },
);

String _shaOf(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pulse-update-test'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ProviderContainer containerWith({
    required UpdateRepository repository,
    required ApkInstaller installer,
    required UpdateStore store,
    int installedCode = 41,
    http.Client Function()? client,
  }) {
    final container = ProviderContainer(
      overrides: [
        updateRepositoryProvider.overrideWithValue(repository),
        apkInstallerProvider.overrideWithValue(installer),
        updateStoreProvider.overrideWith((ref) async => store),
        installedBuildProvider.overrideWith(
          (ref) async => InstalledBuild(
            versionName: '0.1.$installedCode',
            versionCode: installedCode,
          ),
        ),
        if (client != null) updateHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the manifest', () {
    test('a complete per-ABI manifest parses', () {
      final update = AppUpdate.tryParse(<String, Object?>{
        'versionName': '0.1.42',
        'versionCode': 42,
        'notes': <String>['Faster inbox', ' ', 'Sharper ticks'],
        'publishedAt': '2026-11-19T10:00:00Z',
        'abis': <String, Object?>{
          'arm64': <String, Object?>{
            'apkUrl': 'https://example.test/pulse-arm64.apk',
            'sizeBytes': 26 * 1024 * 1024,
            'sha256': 'a' * 64,
          },
          'arm32': <String, Object?>{
            'apkUrl': 'https://example.test/pulse-armv7.apk',
            'sizeBytes': 24 * 1024 * 1024,
            'sha256': 'b' * 64,
          },
        },
      });

      expect(update, isNotNull);
      expect(update!.versionCode, 42);
      expect(update.variants.keys, containsAll(<String>['arm64', 'arm32']));
      expect(update.variantFor('arm64')!.sizeLabel, '26.0 MB');
      expect(update.variantFor('arm32')!.sizeLabel, '24.0 MB');
      expect(update.notes, <String>['Faster inbox', 'Sharper ticks']);
      expect(update.publishedAt, isNotNull);
    });

    test('a flat universal manifest still parses and serves every ABI', () {
      final update = AppUpdate.tryParse(<String, Object?>{
        'versionName': '0.1.41',
        'versionCode': 41,
        'apkUrl': 'https://example.test/pulse.apk',
        'sizeBytes': 1024 * 1024 * 67,
        'sha256': 'c' * 64,
      });

      expect(update, isNotNull);
      expect(update!.variantFor('arm64')!.sizeLabel, '67.0 MB');
      expect(update.variantFor('x86'), isNotNull);
    });

    test('a manifest with only other architectures offers nothing', () {
      final mine = deviceAbiKey();
      final other = mine == 'arm64' ? 'arm32' : 'arm64';
      final update = AppUpdate.tryParse(<String, Object?>{
        'versionName': '0.1.42',
        'versionCode': 42,
        'abis': <String, Object?>{
          other: <String, Object?>{
            'apkUrl': 'https://example.test/pulse-x.apk',
            'sizeBytes': 4096,
            'sha256': 'd' * 64,
          },
        },
      });

      expect(update, isNotNull);
      expect(update!.variantFor(mine), isNull);
    });

    test('an http URL, a short hash or an empty file is not an update', () {
      Map<String, Object?> base() => <String, Object?>{
        'versionName': '0.1.42',
        'versionCode': 42,
        'apkUrl': 'https://example.test/pulse.apk',
        'sizeBytes': 4096,
        'sha256': 'b' * 64,
      };

      expect(
        AppUpdate.tryParse(base()..['apkUrl'] = 'http://example.test/x.apk'),
        isNull,
      );
      expect(AppUpdate.tryParse(base()..['sha256'] = 'abc'), isNull);
      expect(AppUpdate.tryParse(base()..['sizeBytes'] = 0), isNull);
      expect(AppUpdate.tryParse('nonsense'), isNull);
    });

    test('only a bigger build number is newer', () {
      final update = _manifest(sha: 'c' * 64, size: 10, code: 42);
      expect(update.isNewerThan(41), isTrue);
      expect(update.isNewerThan(42), isFalse);
      expect(update.isNewerThan(43), isFalse);
    });
  });

  group('the check', () {
    test('a newer build becomes a prompt', () async {
      final store = UpdateStore(temp);
      final container = containerWith(
        repository: _FakeRepo(_manifest(sha: 'd' * 64, size: 4096)),
        installer: _FakeInstaller(),
        store: store,
      );

      await container.read(updateControllerProvider.notifier).checkAtBoot();

      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.available);
      expect(state.shouldPrompt, isTrue);
      expect(state.progress, isNull);
    });

    test(
      'a universal release still updates a device with no exact ABI',
      () async {
        final container = containerWith(
          repository: _FakeRepo(_flatManifest(sha: 'h' * 64, size: 4096)),
          installer: _FakeInstaller(),
          store: UpdateStore(temp),
        );

        await container.read(updateControllerProvider.notifier).checkAtBoot();

        final state = container.read(updateControllerProvider);
        expect(state.phase, UpdatePhase.available);
        expect(state.variant, isNotNull);
      },
    );

    test('the same build number prompts nothing', () async {
      final container = containerWith(
        repository: _FakeRepo(_manifest(sha: 'e' * 64, size: 4096, code: 41)),
        installer: _FakeInstaller(),
        store: UpdateStore(temp),
      );

      await container.read(updateControllerProvider.notifier).checkAtBoot();

      expect(
        container.read(updateControllerProvider).phase,
        UpdatePhase.upToDate,
      );
      expect(container.read(updateControllerProvider).shouldPrompt, isFalse);
    });

    test(
      '“later” is quiet for this launch only — the next launch asks again',
      () async {
        final store = UpdateStore(temp);
        final repo = _FakeRepo(_manifest(sha: 'f' * 64, size: 4096));

        final first = containerWith(
          repository: repo,
          installer: _FakeInstaller(),
          store: store,
        );
        await first.read(updateControllerProvider.notifier).checkAtBoot();
        await first.read(updateControllerProvider.notifier).remindLater();
        expect(first.read(updateControllerProvider).shouldPrompt, isFalse);

        // A new container over the same files is what a restart looks like: the
        // dismissal must not have survived it.
        final second = containerWith(
          repository: repo,
          installer: _FakeInstaller(),
          store: store,
        );
        await second.read(updateControllerProvider.notifier).checkAtBoot();
        expect(
          second.read(updateControllerProvider).phase,
          UpdatePhase.available,
        );
        expect(second.read(updateControllerProvider).shouldPrompt, isTrue);
      },
    );

    test('coming back to the app re-arms a dismissed prompt', () async {
      final container = containerWith(
        repository: _FakeRepo(_manifest(sha: '9' * 64, size: 4096)),
        installer: _FakeInstaller(),
        store: UpdateStore(temp),
      );

      final controller = container.read(updateControllerProvider.notifier);
      await controller.checkAtBoot();
      await controller.remindLater();
      expect(container.read(updateControllerProvider).shouldPrompt, isFalse);

      // Leaving and re-entering the app is exactly one resume.
      await controller.reconsiderOnReturn();

      expect(container.read(updateControllerProvider).shouldPrompt, isTrue);
    });

    test('a real download still survives "later" and a restart', () async {
      final bytes = List<int>.generate(2048, (i) => i % 249);
      final sha = _shaOf(bytes);
      final store = UpdateStore(temp);
      final repo = _FakeRepo(_manifest(sha: sha, size: bytes.length));

      final first = containerWith(
        repository: repo,
        installer: _FakeInstaller(),
        store: store,
        client: () => MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      await first.read(updateControllerProvider.notifier).checkAtBoot();
      await first.read(updateControllerProvider.notifier).download();
      await first.read(updateControllerProvider.notifier).remindLater();
      expect(first.read(updateControllerProvider).phase, UpdatePhase.ready);

      // Re-entering must skip the network and offer the file already on disk.
      final second = containerWith(
        repository: repo,
        installer: _FakeInstaller(),
        store: store,
        client: () => MockClient((_) async => http.Response('nope', 500)),
      );
      await second.read(updateControllerProvider.notifier).checkAtBoot();
      expect(second.read(updateControllerProvider).phase, UpdatePhase.ready);
      expect(second.read(updateControllerProvider).shouldPrompt, isTrue);
    });
  });

  group('the download', () {
    test('the bytes are verified, committed and never fetched twice', () async {
      final bytes = List<int>.generate(4096, (i) => i % 251);
      final sha = _shaOf(bytes);
      final store = UpdateStore(temp);
      var hits = 0;

      final container = containerWith(
        repository: _FakeRepo(_manifest(sha: sha, size: bytes.length)),
        installer: _FakeInstaller(),
        store: store,
        client: () => MockClient((request) async {
          hits++;
          return http.Response.bytes(bytes, 200);
        }),
      );

      final controller = container.read(updateControllerProvider.notifier);
      await controller.checkAtBoot();
      await controller.download();

      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.ready);
      expect(state.percent, 100);
      expect(state.apkPath, isNotNull);
      expect(File(state.apkPath!).readAsBytesSync(), bytes);
      expect(state.apkPath, contains(deviceAbiKey()));
      expect(hits, 1);

      // A second launch, with the same manifest: the APK is already there.
      final second = containerWith(
        repository: _FakeRepo(_manifest(sha: sha, size: bytes.length)),
        installer: _FakeInstaller(),
        store: store,
        client: () => MockClient((request) async {
          hits++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      await second.read(updateControllerProvider.notifier).checkAtBoot();

      expect(second.read(updateControllerProvider).phase, UpdatePhase.ready);
      expect(second.read(updateControllerProvider).apkPath, isNotNull);
      expect(
        hits,
        1,
        reason: 'a finished download must never be fetched again',
      );
    });

    test('a file whose hash is wrong is deleted, not installed', () async {
      final bytes = List<int>.generate(2048, (i) => i % 97);
      final store = UpdateStore(temp);

      final container = containerWith(
        repository: _FakeRepo(_manifest(sha: 'g' * 64, size: bytes.length)),
        installer: _FakeInstaller(),
        store: store,
        client: () =>
            MockClient((request) async => http.Response.bytes(bytes, 200)),
      );

      final controller = container.read(updateControllerProvider.notifier);
      await controller.checkAtBoot();
      await controller.download();

      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.failed);
      expect(state.apkPath, isNull);
      expect(store.apkFile(42, deviceAbiKey()).existsSync(), isFalse);
      expect(store.partFile(42, deviceAbiKey()).existsSync(), isFalse);
    });
  });

  group('the install', () {
    test('a verified file is handed to the installer', () async {
      final bytes = List<int>.generate(512, (i) => i % 31);
      final installer = _FakeInstaller();
      final store = UpdateStore(temp);

      final container = containerWith(
        repository: _FakeRepo(
          _manifest(sha: _shaOf(bytes), size: bytes.length),
        ),
        installer: installer,
        store: store,
        client: () =>
            MockClient((request) async => http.Response.bytes(bytes, 200)),
      );

      final controller = container.read(updateControllerProvider.notifier);
      await controller.checkAtBoot();
      await controller.download();
      await controller.install();

      expect(installer.installed, hasLength(1));
      expect(
        installer.installed.single,
        endsWith('pulse-42-${deviceAbiKey()}.apk'),
      );
    });

    test(
      'without the permission nothing is installed and we ask for it',
      () async {
        final bytes = List<int>.generate(512, (i) => i % 29);
        final installer = _FakeInstaller(allowed: false);
        final store = UpdateStore(temp);

        final container = containerWith(
          repository: _FakeRepo(
            _manifest(sha: _shaOf(bytes), size: bytes.length),
          ),
          installer: installer,
          store: store,
          client: () =>
              MockClient((request) async => http.Response.bytes(bytes, 200)),
        );

        final controller = container.read(updateControllerProvider.notifier);
        await controller.checkAtBoot();
        await controller.download();
        await controller.install();

        expect(installer.installed, isEmpty);
        expect(
          container.read(updateControllerProvider).message,
          contains('install unknown apps'),
        );
      },
    );
  });

  test('the published manifest shape round-trips', () {
    // Exactly what CI writes in `.github/workflows/flutter-ci.yml`.
    final json = jsonEncode(<String, Object?>{
      'versionName': '0.1.99',
      'versionCode': 99,
      'publishedAt': '2026-11-19T10:00:00Z',
      'notes': <String>['fix(explore): Message opens the real inbox'],
      'abis': <String, Object?>{
        'arm64': <String, Object?>{
          'apkUrl': 'https://github.com/Ngrokmal/project-pulse-/releases/latest/download/pulse-arm64.apk',
          'sizeBytes': 26 * 1024 * 1024,
          'sha256': '1' * 64,
        },
        'arm32': <String, Object?>{
          'apkUrl': 'https://github.com/Ngrokmal/project-pulse-/releases/latest/download/pulse-armv7.apk',
          'sizeBytes': 23 * 1024 * 1024,
          'sha256': '2' * 64,
        },
      },
    });

    final update = AppUpdate.tryParse(jsonDecode(json));
    expect(update, isNotNull);
    expect(update!.variantFor('arm64')!.sizeLabel, '26.0 MB');
    expect(update.notes.single, startsWith('fix(explore)'));
  });
}
