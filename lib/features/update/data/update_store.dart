import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/error/app_failure.dart';

/// The APK on disk, and the small facts around it.
///
/// The point of this class is the user's rule: **download once**. A finished
/// download is remembered in a sidecar file next to the APK that records the
/// hash it was verified against, so the next launch can prove the file is still
/// the right one by size and sidecar instead of hashing 30 MB on the splash
/// screen — and never downloads it again.
///
/// ### One identity, and it is the build number
///
/// Every file this class names is keyed by **the channel build** — the run
/// number the release is called — and by the ABI. Not by Android's `versionCode`:
/// that number is rewritten per ABI (build 53 installs as 2053), so a download
/// that started under one name could be finished under another. That is exactly
/// what happened: the bytes landed as `pulse-53-arm64.apk.part` and the commit
/// looked for `pulse-2053-arm64.apk.part`, found nothing, and threw — after a
/// complete 28 MB download, every single time.
///
/// The parameter is called `build` so the wrong number cannot be passed without
/// the call site reading badly, and [commit] checks the file is really there
/// before it claims success.
///
/// Only the *download* is remembered. A dismissed prompt is deliberately not
/// written here: "later" has to mean "not this time", not "not ever".
class UpdateStore {
  UpdateStore(this.directory);

  final Directory directory;

  static Future<UpdateStore> open() async {
    // Application *support*, not documents: on Android that is `filesDir`, which
    // is the one directory the app's FileProvider is allowed to hand out — and
    // the installer needs a `content://` URI, never a plain path.
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return UpdateStore(dir);
  }

  // The ABI is part of every name: two files for the same build are two
  // different binaries, and reusing the wrong one would be an install of the
  // wrong architecture.
  File apkFile(int build, String abi) =>
      File('${directory.path}/pulse-$build-$abi.apk');

  File partFile(int build, String abi) =>
      File('${directory.path}/pulse-$build-$abi.apk.part');

  File _stampFile(int build, String abi) =>
      File('${directory.path}/pulse-$build-$abi.apk.ok');

  /// A previously finished download, if it is still exactly what the manifest
  /// describes.
  Future<String?> reusableApk({
    required int build,
    required String abi,
    required String sha256,
    required int sizeBytes,
  }) async {
    final apk = apkFile(build, abi);
    final stamp = _stampFile(build, abi);
    if (!apk.existsSync() || !stamp.existsSync()) return null;
    if (apk.lengthSync() != sizeBytes) return null;
    final verified = (stamp.readAsStringSync()).trim().toLowerCase();
    return verified == sha256.toLowerCase() ? apk.path : null;
  }

  /// The bytes are already on this phone, complete and correct, but the commit
  /// never happened — the download died on its very last step, or the app was
  /// killed while it was closing the file.
  ///
  /// This is what makes "download" cost nothing the second time: the file is
  /// hashed, and if it is the right file it is promoted instead of being thrown
  /// away and fetched again.
  Future<String?> finishedPart({
    required int build,
    required String abi,
    required String sha256,
    required int sizeBytes,
    required Future<String> Function(File file) digestOf,
  }) async {
    final part = partFile(build, abi);
    if (!part.existsSync()) return null;
    if (part.lengthSync() != sizeBytes) return null;
    final digest = await digestOf(part);
    if (digest.toLowerCase() != sha256.toLowerCase()) return null;
    return part.path;
  }

  /// Marks a verified download as good and clears the partial.
  ///
  /// It verifies rather than assumes: the part file must exist and (when the
  /// caller knows it) be exactly the size the manifest promised. A failure here
  /// is a [UpdateFailure] that says what to do next, never a raw
  /// `FileSystemException` — those used to reach the screen as "the download
  /// stopped", which was both vague and, in the case that produced it, untrue.
  File commit({
    required int build,
    required String abi,
    required String sha256,
    int? sizeBytes,
  }) {
    final part = partFile(build, abi);
    if (!part.existsSync()) {
      throw const UpdateFailure(
        'file_missing',
        'The download finished but Pulse could not find the file it had just '
        'written. Tap Download update — the next attempt saves it again.',
      );
    }
    if (sizeBytes != null && part.lengthSync() != sizeBytes) {
      // A truncated file is deleted so the retry starts clean.
      part.deleteSync();
      throw const UpdateFailure(
        'file_truncated',
        'The file was saved short of its full size, so it was thrown away. '
        'Tap Download update to fetch it again.',
      );
    }

    try {
      final finalFile = apkFile(build, abi);
      if (finalFile.existsSync()) finalFile.deleteSync();
      final moved = part.renameSync(finalFile.path);
      if (!moved.existsSync() || moved.lengthSync() != part.lengthSync()) {
        throw const UpdateFailure(
          'file_move_failed',
          'The file could not be put where Android expects it. Tap Download '
          'update to try once more.',
        );
      }
      _stampFile(build, abi).writeAsStringSync(sha256.toLowerCase());
      _clearOthers(keep: build);
      return moved;
    } on UpdateFailure {
      rethrow;
    } on FileSystemException {
      throw const UpdateFailure(
        'file_save_failed',
        'Pulse could not save the update on this phone. Free up some space and '
        'tap Download update again.',
      );
    }
  }

  void discard(int build, String abi) {
    for (final file in <File>[
      apkFile(build, abi),
      partFile(build, abi),
      _stampFile(build, abi),
    ]) {
      if (file.existsSync()) file.deleteSync();
    }
  }

  void _clearOthers({required int keep}) {
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('pulse-')) continue;
      // Keep this build's files (every ABI of it), drop the rest.
      if (name.startsWith('pulse-$keep-')) continue;
      try {
        entity.deleteSync();
      } on FileSystemException {
        // Another build's leftovers are not worth failing this download over.
      }
    }
  }
}
