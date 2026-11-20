import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse/core/error/app_failure.dart';
import 'package:pulse/features/update/application/update_controller.dart';
import 'package:pulse/features/update/data/apk_installer.dart';
import 'package:pulse/features/update/data/update_store.dart';
import 'package:pulse/features/update/domain/app_update.dart';
import 'package:pulse/features/update/domain/update_repository.dart';

/// **The download that finished and then threw itself away.**
///
/// The bytes landed under the name of the build (`pulse-53-arm64.apk.part`) and
/// the commit looked for them under Android's versionCode (`2053`) — so every
/// single download ended in a `FileSystemException`, which the screen showed as
/// "The download stopped", and the install button never appeared. Five downloads,
/// five identical failures, 28 MB each.
///
/// These tests pin the identity down from both ends: the file is named after the
/// build, the commit finds it, and the bytes already on disk are never fetched a
/// second time.
class _Repo implements UpdateRepository {
  _Repo(this.update);
  final AppUpdate? update;

  @override
  Future<AppUpdate?> latest() async => update;
}

class _Installer implements ApkInstaller {
  final List<String> installed = <String>[];

  @override
  Future<bool> canInstall() async => true;

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<void> install(String apkPath) async => installed.add(apkPath);
}

String _shaOf(List<int> bytes) => sha256.convert(bytes).toString();

/// The live shape of a release manifest: the build is 53, the arm64 file that
/// carries it is 2053. Passing one where the other belongs is the whole bug.
AppUpdate manifestWith({
  required String sha,
  required int size,
  int build = 53,
}) {
  const base = 'https://example.test/releases/latest/download';
  const index = <String, int>{'arm64': 2, 'arm32': 1, 'x86': 3, 'x64': 4};

  Map<String, Object?> slice(String abi) => <String, Object?>{
    'apkUrl': '$base/pulse-$abi.apk',
    'sizeBytes': size,
    'sha256': sha,
    'versionCode': index[abi]! * 1000 + build,
  };

  final parsed = AppUpdate.tryParse(<String, Object?>{
    'versionName': '0.1.$build',
    'channelBuild': build,
    'versionCode': 2000 + build,
    'apkUrl': '$base/pulse-arm64.apk',
    'sizeBytes': size,
    'sha256': sha,
    'abis': {for (final abi in index.keys) abi: slice(abi)},
  });
  return parsed!;
}

void main() {
  late Directory temp;
  late List<int> bytes;
  late String sha;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pulse-dl');
    bytes = List<int>.generate(4096, (i) => (i * 37) % 251);
    sha = _shaOf(bytes);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  ProviderContainer containerWith({
    required UpdateRepository repository,
    required UpdateStore store,
    ApkInstaller? installer,
    http.Client Function()? client,
    int installed = 51,
  }) {
    final container = ProviderContainer(
      overrides: [
        updateRepositoryProvider.overrideWithValue(repository),
        apkInstallerProvider.overrideWithValue(installer ?? _Installer()),
        updateStoreProvider.overrideWith((ref) async => store),
        installedBuildProvider.overrideWith(
          (ref) async => InstalledBuild(
            versionName: '0.1.$installed',
            versionCode: 2000 + installed,
            channelBuild: installed,
          ),
        ),
        if (client != null) updateHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('a finished download becomes an installable file', () {
    test('the bytes land under the build, and the commit finds them', () async {
      final installer = _Installer();
      final container = containerWith(
        repository: _Repo(manifestWith(sha: sha, size: bytes.length)),
        store: UpdateStore(temp),
        installer: installer,
        client: () => MockClient((_) async => http.Response.bytes(bytes, 200)),
      );

      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      await controller.download();

      final state = container.read(updateControllerProvider);
      expect(
        state.phase,
        UpdatePhase.ready,
        reason: 'a complete, verified download must be ready to install',
      );
      expect(state.message, isNull);
      expect(state.apkPath, isNotNull);
      expect(File(state.apkPath!).existsSync(), isTrue);
      expect(File(state.apkPath!).lengthSync(), bytes.length);

      // And the file is named after the build, not Android's versionCode.
      expect(state.apkPath, contains('pulse-53-'));

      await controller.install();
      expect(installer.installed, [state.apkPath]);
    });

    test('the same build is recognised and never downloaded twice', () async {
      final store = UpdateStore(temp);
      var requests = 0;
      final manifest = manifestWith(sha: sha, size: bytes.length);

      final first = containerWith(
        repository: _Repo(manifest),
        store: store,
        client: () => MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      await first.read(updateControllerProvider.notifier).check();
      await first.read(updateControllerProvider.notifier).download();
      expect(first.read(updateControllerProvider).phase, UpdatePhase.ready);
      expect(requests, 1);

      // A new container over the same directory is a restart: the check alone
      // must find the file and offer Install.
      final second = containerWith(
        repository: _Repo(manifest),
        store: store,
        client: () => MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      await second.read(updateControllerProvider.notifier).check();
      expect(second.read(updateControllerProvider).phase, UpdatePhase.ready);
      expect(
        requests,
        1,
        reason: 'a verified file on disk is never fetched again',
      );
    });
  });

  group('the download that died on its last step', () {
    test('a complete, uncommitted file is promoted instead of re-downloaded', () async {
      final store = UpdateStore(temp);
      // Exactly what the old code left behind: the right bytes, under the right
      // build name, never committed.
      final abi = deviceAbiKey();
      final part = store.partFile(53, abi)..writeAsBytesSync(bytes);
      expect(part.existsSync(), isTrue);

      var requests = 0;
      final container = containerWith(
        repository: _Repo(manifestWith(sha: sha, size: bytes.length)),
        store: store,
        client: () => MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );

      final controller = container.read(updateControllerProvider.notifier);
      await controller.check();
      await controller.download();

      final state = container.read(updateControllerProvider);
      expect(state.phase, UpdatePhase.ready);
      expect(requests, 0, reason: 'the bytes were already here');
      expect(File(state.apkPath!).existsSync(), isTrue);
      expect(
        part.existsSync(),
        isFalse,
        reason: 'the partial was promoted away',
      );
    });

    test('a commit with nothing to move says so, in words that help', () {
      final store = UpdateStore(temp);
      expect(
        () => store.commit(build: 53, abi: 'arm64', sha256: sha),
        throwsA(
          isA<UpdateFailure>().having(
            (failure) => failure.userMessage,
            'message',
            contains('Download update'),
          ),
        ),
      );
    });

    test('a truncated file is thrown away, never stamped as good', () {
      final store = UpdateStore(temp);
      store.partFile(53, 'arm64').writeAsBytesSync(bytes.sublist(0, 100));
      expect(
        () => store.commit(
          build: 53,
          abi: 'arm64',
          sha256: sha,
          sizeBytes: bytes.length,
        ),
        throwsA(isA<UpdateFailure>()),
      );
      expect(store.partFile(53, 'arm64').existsSync(), isFalse);
      expect(store.apkFile(53, 'arm64').existsSync(), isFalse);
    });

    test(
      'cancelling removes the partial of the build being downloaded',
      () async {
        final store = UpdateStore(temp);
        final container = containerWith(
          repository: _Repo(manifestWith(sha: sha, size: bytes.length)),
          store: store,
        );
        final controller = container.read(updateControllerProvider.notifier);
        await controller.check();

        store
            .partFile(53, deviceAbiKey())
            .writeAsBytesSync(bytes.sublist(0, 10));
        await controller.cancelDownload();

        expect(store.partFile(53, deviceAbiKey()).existsSync(), isFalse);
        expect(
          container.read(updateControllerProvider).phase,
          UpdatePhase.available,
        );
      },
    );
  });
}
