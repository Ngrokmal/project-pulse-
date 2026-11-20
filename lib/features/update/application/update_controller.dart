import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/error/app_failure.dart';
import '../data/apk_installer.dart';
import '../data/github_update_repository.dart';
import '../data/update_store.dart';
import '../domain/app_update.dart';
import '../domain/update_repository.dart';

/// Where the update flow is, in one enum, so the page can never show two things
/// at once.
enum UpdatePhase {
  /// Nothing has been asked yet.
  idle,

  /// Asking the release channel.
  checking,

  /// The installed build is the newest one.
  upToDate,

  /// A newer build exists and has not been downloaded yet.
  available,

  /// Bytes are on their way in.
  downloading,

  /// The APK is on disk, verified, waiting for the installer.
  ready,

  /// The system installer is open.
  installing,

  /// Something went wrong; [UpdateState.message] says what.
  failed,
}

/// The whole update screen, as one immutable value.
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.update,
    this.variant,
    this.received = 0,
    this.total = 0,
    this.apkPath,
    this.message,
    this.canInstall = false,
    this.skipped = false,
  });

  final UpdatePhase phase;
  final AppUpdate? update;

  /// The file chosen for *this* device's CPU — the only one worth showing a
  /// size or a hash for.
  final UpdateVariant? variant;
  final int received;
  final int total;
  final String? apkPath;
  final String? message;

  /// False while Android still needs the "install unknown apps" permission.
  final bool canInstall;

  /// The user pressed *later* for this exact build — **in this run of the app
  /// only**. It is never written to disk, so the next launch (or the next time
  /// the app comes back to the front) asks again.
  final bool skipped;

  /// 0…1, or `null` when the server did not send a content length.
  double? get progress {
    if (phase != UpdatePhase.downloading) {
      return phase == UpdatePhase.ready ? 1 : null;
    }
    if (total <= 0) return null;
    return (received / total).clamp(0.0, 1.0);
  }

  int get percent => ((progress ?? 0) * 100).round().clamp(0, 100);

  /// Should the app interrupt a launch to show this?
  bool get shouldPrompt =>
      !skipped &&
      (phase == UpdatePhase.available ||
          phase == UpdatePhase.downloading ||
          phase == UpdatePhase.ready);

  bool get isWorking =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.installing;

  UpdateState copyWith({
    UpdatePhase? phase,
    AppUpdate? update,
    UpdateVariant? variant,
    int? received,
    int? total,
    String? apkPath,
    String? message,
    bool? canInstall,
    bool? skipped,
    bool clearMessage = false,
    bool clearApkPath = false,
  }) {
    return UpdateState(
      phase: phase ?? this.phase,
      update: update ?? this.update,
      variant: variant ?? this.variant,
      received: received ?? this.received,
      total: total ?? this.total,
      apkPath: clearApkPath ? null : (apkPath ?? this.apkPath),
      message: clearMessage ? null : (message ?? this.message),
      canInstall: canInstall ?? this.canInstall,
      skipped: skipped ?? this.skipped,
    );
  }
}

/// The installed build, read from the APK itself rather than from a constant, so
/// a sideloaded CI artifact always knows exactly what it is.
/// The ABI key this manifest uses for this device.
///
/// `dart:ffi` already knows the architecture the app was built for; this only
/// maps it to the words the release manifest uses (`arm64`, `arm32`, `x64`,
/// `x86`). Anything unrecognised falls back to `arm64`, which is what almost
/// every phone in the world runs.
String deviceAbiKey() {
  final abi = Abi.current();
  if (abi == Abi.androidArm64 ||
      abi == Abi.androidRiscv64 ||
      abi == Abi.iosArm64 ||
      abi == Abi.iosArm64e ||
      abi == Abi.macosArm64 ||
      abi == Abi.macosArm64e ||
      abi == Abi.linuxArm64 ||
      abi == Abi.windowsArm64 ||
      abi == Abi.fuchsiaArm64) {
    return 'arm64';
  }
  if (abi == Abi.androidArm || abi == Abi.iosArm || abi == Abi.linuxArm) {
    return 'arm32';
  }
  if (abi == Abi.androidX64 ||
      abi == Abi.iosX64 ||
      abi == Abi.macosX64 ||
      abi == Abi.linuxX64 ||
      abi == Abi.windowsX64 ||
      abi == Abi.fuchsiaX64) {
    return 'x64';
  }
  if (abi == Abi.androidIA32 ||
      abi == Abi.linuxIA32 ||
      abi == Abi.windowsIA32 ||
      abi == Abi.linuxRiscv32) {
    return 'x86';
  }
  return 'arm64';
}

class InstalledBuild {
  const InstalledBuild({required this.versionName, required this.versionCode});

  final String versionName;
  final int versionCode;

  String get label => 'v$versionName ($versionCode)';
}

final installedBuildProvider = FutureProvider<InstalledBuild>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return InstalledBuild(
    versionName: info.version.isEmpty ? '0.0.0' : info.version,
    versionCode: int.tryParse(info.buildNumber) ?? 0,
  );
});

final updateRepositoryProvider = Provider<UpdateRepository>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GithubUpdateRepository(
    client,
    manifestUrl: AppConfig.updateManifestUrl,
  );
});

final updateStoreProvider = FutureProvider<UpdateStore>(
  (ref) => UpdateStore.open(),
);

final apkInstallerProvider = Provider<ApkInstaller>(
  (ref) => const ApkInstaller(),
);

/// One place that hands out the HTTP client used for the APK itself, so a test
/// can drive a whole download — progress, size check, hash check — without a
/// network.
final updateHttpClientProvider = Provider<http.Client Function()>(
  (ref) => http.Client.new,
);

/// Checks, downloads, verifies, installs.
///
/// Three rules shape all of it:
///  • **never block the launch** — the boot check has a short budget and every
///    failure is silent, because an offline phone still belongs in the app;
///  • **download once** — a finished, verified APK is reused from disk by
///    sidecar hash, so leaving the app before pressing Install does not cost the
///    user another 30 MB;
///  • **never hand over an unverified file** — the SHA-256 from the manifest is
///    checked before the installer is even allowed to look at it.
class UpdateController extends Notifier<UpdateState> {
  http.Client? _downloadClient;

  @override
  UpdateState build() {
    ref.onDispose(() {
      _downloadClient?.close();
      _downloadClient = null;
    });
    return const UpdateState();
  }

  UpdateRepository get _repository => ref.read(updateRepositoryProvider);
  ApkInstaller get _installer => ref.read(apkInstallerProvider);

  /// Called once, from the splash screen. Returns when it is done or when its
  /// budget runs out — whichever comes first.
  Future<void> checkAtBoot({
    Duration budget = const Duration(milliseconds: 2500),
  }) async {
    if (!AppConfig.updatesEnabled) return;
    state = state.copyWith(phase: UpdatePhase.checking, clearMessage: true);
    try {
      await _check().timeout(budget);
    } on Object {
      // Silent: an update check must never be the reason a launch fails.
      if (state.phase == UpdatePhase.checking) {
        state = state.copyWith(phase: UpdatePhase.idle);
      }
    }
  }

  /// An explicit check (used by the update page's retry and by Settings).
  Future<void> check() async {
    state = state.copyWith(phase: UpdatePhase.checking, clearMessage: true);
    try {
      await _check();
    } on AppFailure catch (failure) {
      state = state.copyWith(
        phase: UpdatePhase.failed,
        message: failure.userMessage,
      );
    } on Object {
      state = state.copyWith(
        phase: UpdatePhase.failed,
        message: 'Could not reach the release channel.',
      );
    }
  }

  Future<void> _check() async {
    final build = await ref.read(installedBuildProvider.future);
    final latest = await _repository.latest();
    final canInstall = await _installer.canInstall();

    if (latest == null || !latest.isNewerThan(build.versionCode)) {
      state = state.copyWith(
        phase: UpdatePhase.upToDate,
        canInstall: canInstall,
        clearMessage: true,
      );
      return;
    }

    final abi = deviceAbiKey();
    final variant = latest.variantFor(abi);
    if (variant == null) {
      // The channel published only other architectures. Say nothing and leave
      // the app alone rather than offer a download that cannot install.
      state = state.copyWith(
        phase: UpdatePhase.upToDate,
        canInstall: canInstall,
      );
      return;
    }

    final store = await ref.read(updateStoreProvider.future);
    final reusable = await store.reusableApk(
      versionCode: latest.versionCode,
      abi: abi,
      sha256: variant.sha256,
      sizeBytes: variant.sizeBytes,
    );
    // A dismissal only ever applies to the build it was given for, and only
    // while this app session is alive.
    final skipped =
        state.skipped && state.update?.versionCode == latest.versionCode;

    state = UpdateState(
      phase: reusable == null ? UpdatePhase.available : UpdatePhase.ready,
      update: latest,
      variant: variant,
      apkPath: reusable,
      total: variant.sizeBytes,
      received: reusable == null ? 0 : variant.sizeBytes,
      canInstall: canInstall,
      skipped: skipped,
    );
  }

  /// Downloads to a `.part` file, verifies it, then commits it under its real
  /// name. Progress is published at most every 80 ms: a rebuild per network
  /// packet is how a download makes the UI stutter.
  Future<void> download() async {
    final update = state.update;
    final variant = state.variant;
    if (update == null ||
        variant == null ||
        state.phase == UpdatePhase.downloading) {
      return;
    }

    final abi = deviceAbiKey();
    final store = await ref.read(updateStoreProvider.future);
    final part = store.partFile(update.versionCode, abi);
    if (part.existsSync()) part.deleteSync();

    state = state.copyWith(
      phase: UpdatePhase.downloading,
      received: 0,
      total: variant.sizeBytes,
      clearMessage: true,
      clearApkPath: true,
    );

    final client = ref.read(updateHttpClientProvider)();
    _downloadClient = client;
    IOSink? sink;

    try {
      final request = http.Request('GET', Uri.parse(variant.apkUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw ServerFailure(safeCode: 'update_download_${response.statusCode}');
      }

      sink = part.openWrite();
      var received = 0;
      var lastEmit = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastEmit >= 80) {
          lastEmit = now;
          state = state.copyWith(received: received);
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (received != variant.sizeBytes) {
        throw const ServerFailure(safeCode: 'update_size_mismatch');
      }

      final digest = await _sha256OfFile(part);
      if (digest != variant.sha256) {
        if (part.existsSync()) part.deleteSync();
        throw const ServerFailure(safeCode: 'update_hash_mismatch');
      }

      final file = store.commit(
        versionCode: update.versionCode,
        abi: abi,
        sha256: variant.sha256,
      );

      state = state.copyWith(
        phase: UpdatePhase.ready,
        apkPath: file.path,
        received: received,
        total: received,
        canInstall: await _installer.canInstall(),
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(
        phase: UpdatePhase.failed,
        message: failure.userMessage,
      );
    } on Object {
      state = state.copyWith(
        phase: UpdatePhase.failed,
        message:
            'The download stopped. You can try again — the app will pick up '
            'from the beginning rather than leave a half file.',
      );
    } finally {
      await sink?.close();
      client.close();
      if (identical(_downloadClient, client)) _downloadClient = null;
    }
  }

  /// Cancels an in-flight download and forgets the partial file.
  Future<void> cancelDownload() async {
    final client = _downloadClient;
    _downloadClient = null;
    client?.close();
    final update = state.update;
    if (update == null) return;
    final store = await ref.read(updateStoreProvider.future);
    final part = store.partFile(update.versionCode, deviceAbiKey());
    if (part.existsSync()) part.deleteSync();
    state = state.copyWith(phase: UpdatePhase.available, received: 0);
  }

  /// Hands the verified APK to Android. If the permission is missing this asks
  /// for it instead of failing quietly.
  Future<void> install() async {
    final path = state.apkPath;
    if (path == null) return;

    if (!await _installer.canInstall()) {
      state = state.copyWith(
        canInstall: false,
        phase: UpdatePhase.ready,
        message: 'Allow “install unknown apps” for Pulse, then come back.',
      );
      await _installer.openInstallSettings();
      return;
    }

    state = state.copyWith(phase: UpdatePhase.installing, clearMessage: true);
    try {
      await _installer.install(path);
      // The installer takes over from here; when the user comes back the build
      // is either updated (and the check returns up to date) or it is not.
      state = state.copyWith(phase: UpdatePhase.ready);
    } on Object {
      state = state.copyWith(
        phase: UpdatePhase.ready,
        message: 'Android refused to open the installer for that file.',
      );
    }
  }

  /// Re-reads the permission after the user comes back from Settings.
  Future<void> refreshPermission() async {
    final canInstall = await _installer.canInstall();
    state = state.copyWith(canInstall: canInstall, clearMessage: canInstall);
  }

  /// "Later": quiet until the app is left and entered again.
  ///
  /// Nothing is written to disk on purpose. The rule the user asked for is
  /// **every launch asks**: tapping *Now now / Later* may get you into the app
  /// this time, but the next time the app is opened — or brought back to the
  /// front — the update page is offered again until it is installed.
  Future<void> remindLater() async {
    if (state.update == null) return;
    state = state.copyWith(skipped: true, clearMessage: true);
  }

  /// Called whenever the app returns to the foreground.
  ///
  /// Re-arms the prompt (clearing any "later" pressed earlier in the session)
  /// and asks the release channel again, so an APK that was downloaded but not
  /// installed is offered immediately rather than silently.
  Future<void> reconsiderOnReturn() async {
    if (!AppConfig.updatesEnabled) return;
    if (state.isWorking) return;
    if (state.skipped) state = state.copyWith(skipped: false);
    await check();
  }

  /// Called from the page once a build has actually been installed.
  Future<void> forgetDownload() async {
    final code = state.update?.versionCode;
    final store = await ref.read(updateStoreProvider.future);
    if (code != null) store.discard(code, deviceAbiKey());
    state = const UpdateState();
  }

  void dismissMessage() => state = state.copyWith(clearMessage: true);

  static Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
